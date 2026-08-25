; basic.sol -- an interpreter for BASIC: tokenise, parse, run.
;
; Run with:  ./bin/solas programs/basic.sol && ./bin/solvm programs/basic.sob
;
; The eleventh program here, and the first that is an interpreter for *another
; language* rather than a tool for this one. The other ten read text, walk
; trees, copy files or run commands; this one holds a second language's state --
; a variable table, a program counter, a listing -- and is judged by whether a
; program written fifty years ago in a different notation gives the answer it
; gave then.
;
; It is deliberately not a BASIC of its own. The dialect is **ECMA-55 Minimal
; BASIC (1978)**, because a published standard means "done" is decided by
; somebody other than the author of the interpreter, and because Minimal BASIC
; is small enough to finish: nineteen keywords and eleven supplied functions.
;
; ---------------------------------------------------------------------------
; What is here so far
;
; **Stage one of six: `LET`, `PRINT`, `REM`, `END`, and the whole numeric
; expression grammar.** No control flow yet -- a listing runs from its lowest
; line number to its highest and stops -- so nothing below needs a jump. What is
; built is the part every later stage sits on: the tokeniser, the expression
; parser and its tree, the line table, the run loop and its program counter, and
; `PRINT`'s output rules, which are stranger than they look and are why the
; demonstrations at the bottom have spaces in them where you would not expect
; any.
;
; The stages after this one, in order: control flow (`GOTO`, `IF-THEN`,
; `FOR/NEXT`, `GOSUB/RETURN`, `ON-GOTO`, `STOP`); the supplied functions; data
; (`DIM`, arrays, `READ/DATA/RESTORE`, `INPUT`, `DEF FN`, `RANDOMIZE`); the rest
; of `PRINT`'s formatting; then listings read from `.bas` files in
; `programs/basic/` rather than written inline here.
;
; ---------------------------------------------------------------------------
; Why a line-numbered language is the easy case, which is not the obvious way round
;
; Line numbers have a bad name, and for this language they are a gift.
; [3.5](../docs/ROADMAP.md#35-recursion-is-limited-to-about-254-levels) caps
; recursion at about 254 frames, and an interpreter for a modern language would
; meet that cap at once: a tree-walking evaluator spends frames in proportion to
; how deeply the *source* nests, so a long function would run out of machine
; before it ran out of program.
;
; A line-numbered BASIC never nests. Its run loop is a program counter over a
; sorted table of lines, and every construct that looks like nesting -- `GOSUB`,
; `FOR` -- is an explicit stack in an array, which is heap and not frames. So
; the only recursion here is in the expression parser, it runs once at load
; rather than once per execution, and BASIC expressions are shallow.
;
; [evaluator.sol](evaluator.sol) reaches 83 brackets with a three-level grammar.
; This one has four levels and reaches **60**, measured at the bottom of this
; file. No BASIC program written by a person will come near either number.

@include "scan.sol".
@include "control.sol".

; ---------------------------------------------------------------------------
; Characters
;
; BASIC is an uppercase language. The source is *not* uppercased wholesale,
; because that would reach inside string literals and change what a program
; prints -- `PRINT "Hello"` must still say Hello. Only word tokens are folded,
; at the point they are made.
;
; Each of these takes nil without complaining, because the one caller that looks
; ahead (`peekAt`, in `tokenise`) can be looking at the end of the line. A
; character class asked about the absence of a character should answer no.

digits := "0123456789".
letters := "ABCDEFGHIJKLMNOPQRSTUVWXYZ".

isDigit := { c | c:notNil:and({ digits:indexOf(c):notNil }) }.
isLetter := { c | c:notNil:and({ letters:indexOf(c:asUppercase):notNil }) }.
isSpace := { c | c:notNil:and({ c:equals(" "):or({ c:equals("\t") }) }) }.

; ---------------------------------------------------------------------------
; Tokens

token := object:new.
token:kind := 'word.       ; 'number 'string 'word 'punct
token:text := "".

makeToken := { kind, text | | t |
    t := token:new. t:kind := kind. t:text := text. t }.

; ---------------------------------------------------------------------------
; The tree
;
; The same shape [evaluator.sol](evaluator.sol) uses, for the same reason: a
; node is an object with a kind and the fields that kind needs, and the fields
; it does not need are nil.

node := object:new.
node:kind := 'number.      ; 'number 'string 'variable 'binary 'negate
node:value := nil.         ; 'number, 'string
node:name := "".           ; 'variable
node:op := "".             ; 'binary
node:left := nil.
node:right := nil.

numberNode := { v | | n | n := node:new. n:kind := 'number. n:value := v. n }.
stringNode := { v | | n | n := node:new. n:kind := 'string. n:value := v. n }.
variableNode := { name | | n | n := node:new. n:kind := 'variable. n:name := name. n }.
binaryNode := { op, l, r | | n |
    n := node:new. n:kind := 'binary. n:op := op. n:left := l. n:right := r. n }.
negateNode := { x | | n | n := node:new. n:kind := 'negate. n:left := x. n }.

; ---------------------------------------------------------------------------
; Statements
;
; A statement is parsed once, at load, into one of these. The run loop then
; walks the objects rather than the text, which is not an optimisation so much
; as the difference between an interpreter and a toy: a `FOR` loop in stage two
; will run its body tens of thousands of times, and re-reading the characters
; each pass would make the cost of the loop the cost of parsing it.

statement := object:new.
statement:kind := 'rem.    ; 'rem 'let 'print 'end
statement:name := "".      ; 'let
statement:expr := nil.     ; 'let
statement:items := nil.    ; 'print

; A `PRINT` item is an expression and the separator that came *after* it, which
; is what decides where the next thing goes -- so the separator belongs to the
; item on its left rather than sitting between two of them.
printItem := object:new.
printItem:expr := nil.
printItem:sep := 'none.    ; 'none 'comma 'semi

; ---------------------------------------------------------------------------
; The machine
;
; An object rather than a set of globals, so two listings can be in flight at
; once. That is the shape [lib/scan.sol](../lib/scan.sol) settled on after
; [lib/json.sol](../lib/json.sol) spent four releases unable to parse one
; document while parsing another, and it costs nothing to do it right the first
; time.

basic := object:new.
basic:lines := nil.        ; line number -> statement
basic:order := nil.        ; line numbers, sorted: the run order
basic:pc := #1.            ; an index into `order`, not a line number
basic:vars := nil.
basic:running := false.
basic:atLine := #0.        ; the line being parsed or run, for error messages
basic:out := "".           ; the print line being built -- see `flush`
basic:tokens := nil.       ; the line being parsed, tokenised
basic:cursor := #1.        ; the index of the next unread token

; Every failure names the line it happened on, because in a language whose
; control flow is line numbers that is the only address a person has.
basic:fail := { message |
    error:raise("line {}: {}":fill([self:atLine, message])) }.

; ---------------------------------------------------------------------------
; Tokenising
;
; One line at a time, not the whole listing, because BASIC is line-oriented and
; because `REM` swallows the rest of its line as raw text -- text that need not
; tokenise at all. `10 REM DON'T` is a legal line and an apostrophe is not a
; token, so `REM` has to be recognised before the tokeniser sees it and not
; after.
;
; The cursor is [lib/scan.sol](../lib/scan.sol)'s, which makes this the sixth
; file to use it and the first that is not a rewrite of a cursor it had already
; written for itself.
;
; The dispatch is [control.sol](../lib/control.sol)'s `ifElseIf`, and this is
; the shape that file's own example is written in: a scanner deciding what a
; character starts. [disasm.sol](disasm.sol) reaches for it in the same place --
; deciding what a constant tag means -- which is two programs arriving at one
; use, and a fair sign the library named the right thing. Flat, five arms, the last one the default because it is
; last -- against a four-deep nest of `ifElse` closing with `}) }) }) })`.
;
; **It is not free and it is affordable here.** Tokenising 2,000 lines takes
; 0.32s as a nest and 0.43s this way, a third more; a listing anybody actually
; types is a few hundred lines, so that is single-digit milliseconds. And it
; costs no depth at all, because this loop is not inside the recursion -- the
; measurement at the bottom of the file reads 60 either way. Both halves of
; control.sol's advice, checked rather than quoted.

basic:tokenise := { text | | s, out, c |
    s := scan:on(text).
    out := array:new.
    { s:atEnd:not }:whileTrue({
        c := s:peek.
        [ { isSpace:value(c) },   { s:step },
          { isDigit:value(c):or({ c:equals("."):and({
                isDigit:value(s:peekAt(#1)) }) }) },
                                  { out:add(self:numberToken(s)) },
          { isLetter:value(c) },  { out:add(self:wordToken(s)) },
          { c:equals("\"") },      { out:add(self:quotedToken(s)) },
                                  { out:add(self:punctToken(s)) } ]:ifElseIf }).
    out }.

; A numeric literal: digits, an optional fraction, an optional exponent. The
; text is kept and converted later by `asFloat`, which already reads every one
; of these forms -- so this only has to decide where the number *ends*.
basic:numberToken := { s | | start |
    start := s:pos.
    s:skipWhile({ c | isDigit:value(c) }).
    s:match("."):ifTrue({ s:skipWhile({ c | isDigit:value(c) }) }).
    s:peek:notNil:and({ s:peek:asUppercase:equals("E") }):ifTrue({
        s:step.
        s:match("+"):ifFalse({ s:match("-") }).
        s:skipWhile({ c | isDigit:value(c) }) }).
    makeToken:value('number, s:since(start)) }.

; Folded to uppercase here and nowhere else, so `print x` and `PRINT X` are one
; program while `PRINT "x"` still prints a small x.
basic:wordToken := { s |
    makeToken:value('word,
        s:takeWhile({ c | isLetter:value(c):or({ isDigit:value(c) }) }):asUppercase) }.

; Minimal BASIC has no escapes inside a string and so no way to write a quote in
; one. That is the standard rather than a shortcut taken here: the closing quote
; is simply the next one.
basic:quotedToken := { s | | text |
    s:step.
    text := s:takeUntil({ c | c:equals("\"") }).
    s:match("\""):ifFalse({ self:fail("a string was never closed") }).
    makeToken:value('string, text) }.

; The two-character relational operators are read now although nothing until
; stage two can use one, because the alternative is a tokeniser that reports `<`
; and `=` separately and an `IF` that has to put them back together.
basic:punctToken := { s | | c |
    c := s:next.
    c:equals("<"):ifTrue({
        s:match("="):ifElse({ c := "<=" }, { s:match(">"):ifTrue({ c := "<>" }) }) }).
    c:equals(">"):ifTrue({ s:match("="):ifTrue({ c := ">=" }) }).
    "+-*/^(),;=<>":indexOf(c:at(#1)):isNil:ifTrue({
        self:fail("'{}' means nothing here":fill([c])) }).
    makeToken:value('punct, c) }.

; ---------------------------------------------------------------------------
; Reading a listing
;
; A line is a number and then a statement. The number is not decoration: it is
; the line's name, the thing `GOTO` takes an argument of in stage two, and the
; order the program runs in -- which is the order of the *numbers* and not the
; order they were typed.

basic:load := { source |
    self:lines := dictionary:new.
    self:vars := dictionary:new.
    self:out := "".
    source:split("\n"):do({ line | self:loadLine(line) }).
    self:order := self:lines:keys:sorted }.

basic:loadLine := { line | | s, number, rest |
    s := scan:on(line).
    s:skipWhile({ c | isSpace:value(c) }).
    s:atEnd:ifFalse({
        number := s:takeWhile({ c | isDigit:value(c) }).
        number:equals(""):ifTrue({
            self:atLine := #0.
            self:fail("a line must start with a line number: {}":fill([line:trim])) }).
        self:atLine := number:asInteger.

        ; Two lines with one number is a mistake in a listing rather than a
        ; redefinition: the second would silently win, and which of the two ran
        ; would depend on nothing the person reading the listing can see.
        self:lines:includes(self:atLine):ifTrue({
            self:fail("line {} appears twice":fill([self:atLine])) }).

        rest := s:rest:trim.
        rest:equals(""):ifTrue({
            self:fail("this line has a number and nothing else") }).
        self:lines:atPut(self:atLine, self:parseStatement(rest)) }) }.

; ---------------------------------------------------------------------------
; Which statement it is
;
; A dictionary of blocks, keyed by the keyword. There are three ways to write a
; dispatch in this language and this is the third of them, so it is worth saying
; why rather than leaving it to look like the first thing that came to mind.
;
; A **staircase of `ifElse`** is out because there are nineteen keywords to
; come and [3.2](../docs/ROADMAP.md#32-no-non-local-return) gives no early
; return to leave a chain from, so it would be nineteen levels deep and a wall
; of brackets at the end.
;
; **[ifElseIf](../lib/control.sol)** is the library's answer to exactly that,
; and it is the right shape for a flat dispatch -- the tokeniser below uses it.
; It is the wrong shape *here* because it tests its conditions in order: with
; nineteen keywords, recognising `STOP` means nineteen block calls and nineteen
; string comparisons. A dictionary asks once. The trade turns on whether the
; conditions are arbitrary questions or all the same question asked about
; different constants, and a keyword table is the second.
;
; Each block is handed the machine, since a block in a dictionary is not a
; method and has no `self` of its own. They are bound at the top level, where
; the frame they capture lasts as long as the program does; a dictionary of
; blocks built inside a method would fall foul of
; [3.1](../docs/ROADMAP.md#31-capturing-blocks-cannot-escape-their-frame).

parsers := dictionary:new.

basic:parseStatement := { text | | tokens, keyword |
    ; `REM` is tested against the raw text before anything is tokenised, because
    ; what follows it is not a token sequence. A line beginning `REMOVE` is a
    ; remark too: the standard says the rest of the line is ignored after `REM`,
    ; and every BASIC ever written reads that as literally as this does.
    text:size:greaterOrEqual(#3)
        :and({ text:copyFrom(#1, #3):asUppercase:equals("REM") })
        :ifElse({ self:statementOf('rem) }, {
            tokens := self:tokenise(text).
            tokens:size:equals(#0):ifTrue({ self:fail("there is no statement here") }).
            keyword := tokens:at(#1).
            keyword:kind:equals('word):ifFalse({
                self:fail("a statement starts with a keyword, not '{}'"
                    :fill([keyword:text])) }).
            parsers:includes(keyword:text):ifFalse({
                self:fail("'{}' is not a statement this understands yet"
                    :fill([keyword:text])) }).
            parsers:at(keyword:text):value(self, tokens) }) }.

basic:statementOf := { kind | | st |
    st := statement:new. st:kind := kind. st }.

; ECMA-55 requires the word `LET`. Later BASICs made it optional and this one
; does not, because the standard is the whole reason for having chosen a dialect
; and the first convenience is the one that makes the second hard to refuse.
parsers:atPut("LET", { m, tokens | | st |
    tokens:size:lessThan(#4):ifTrue({
        m:fail("LET needs a variable, an = and a value") }).
    st := m:statementOf('let).
    st:name := m:variableName(tokens:at(#2)).
    tokens:at(#3):text:equals("="):ifFalse({
        m:fail("LET needs an = after the variable") }).
    st:expr := m:parse(tokens, #4).
    st }).

parsers:atPut("END", { m, tokens |
    tokens:size:equals(#1):ifFalse({ m:fail("END takes nothing after it") }).
    m:statementOf('end) }).

; A numeric variable in Minimal BASIC is a letter, or a letter and one digit.
; Two hundred and eighty-six of them, and that is the whole namespace -- so
; `TOTAL` is not a long variable name, it is five of them run together.
basic:variableName := { t |
    t:kind:equals('word):ifFalse({
        self:fail("'{}' is not a variable":fill([t:text])) }).
    t:text:size:equals(#1):and({ isLetter:value(t:text) })
        :or({ t:text:size:equals(#2)
                :and({ isLetter:value(t:text:at(#1)) })
                :and({ isDigit:value(t:text:at(#2)) }) })
        :ifFalse({ self:fail(
            "'{}' is not a variable: a letter, or a letter and a digit"
                :fill([t:text])) }).
    t:text }.

; ---------------------------------------------------------------------------
; PRINT
;
; The separators are the statement. `,` moves to the next print zone and `;`
; moves to nowhere at all, and either of them at the *end* of the line holds the
; line open so that the next `PRINT` continues it.

basic:isSeparator := { t |
    t:text:equals(","):or({ t:text:equals(";") }) }.

parsers:atPut("PRINT", { m, tokens | | st, i, item, t |
    st := m:statementOf('print).
    st:items := array:new.
    i := #2.
    { i:lessOrEqual(tokens:size) }:whileTrue({
        item := printItem:new.
        item:expr := nil.
        item:sep := 'none.
        m:isSeparator(tokens:at(i)):ifFalse({
            item:expr := m:parse(tokens, i).
            i := m:cursor }).
        i:lessOrEqual(tokens:size):ifTrue({
            t := tokens:at(i).
            t:text:equals(","):ifTrue({ item:sep := 'comma. i := i:add(#1) }).
            t:text:equals(";"):ifTrue({ item:sep := 'semi. i := i:add(#1) }) }).
        st:items:add(item) }).
    st }).

; ---------------------------------------------------------------------------
; The expression grammar, which is the standard's and not the obvious one
;
;     expression = [sign] term { ('+' | '-') term }
;     term       = factor { ('*' | '/') factor }
;     factor     = primary { '^' primary }
;     primary    = number | string | variable | '(' expression ')'
;
; Two things in it will surprise anyone who knows a later BASIC:
;
;   * **A sign is only allowed at the front.** `-2*3` is a legal expression and
;     `2*-3` is not, because the grammar admits a sign before the first term and
;     nowhere else. Every BASIC after this one relaxed it. Following the
;     standard here is the point of having chosen one.
;
;   * **`^` groups to the left.** `2^3^2` is 64 in Minimal BASIC and 512 almost
;     everywhere since, the standard saying that operators of equal precedence
;     are performed left to right and making no exception for this one.
;
; The token cursor lives in a slot rather than being passed down and returned
; back up, which is the same reason [lib/scan.sol](../lib/scan.sol) exists: an
; index that has to travel alongside every value turns every parse function into
; a pair.

basic:parse := { tokens, from |
    self:tokens := tokens.
    self:cursor := from.
    self:expression }.

basic:peekToken := {
    self:cursor:greaterThan(self:tokens:size)
        :ifElse({ nil }, { self:tokens:at(self:cursor) }) }.

basic:takeToken := { | t |
    t := self:peekToken.
    t:isNil:ifTrue({ self:fail("the line ends in the middle of an expression") }).
    self:cursor := self:cursor:add(#1).
    t }.

; Whether the next token is one of a set of one-character operators, without
; moving. A string of the characters rather than an array of them, which reads
; better at the call sites and is the same test.
basic:atOneOf := { set | | t |
    t := self:peekToken.
    t:isNil:ifElse({ false },
        { t:kind:equals('punct):and({ t:text:size:equals(#1) })
            :and({ set:indexOf(t:text):notNil }) }) }.

basic:expression := { | left, op |
    left := self:atOneOf("+-"):ifElse(
        { op := self:takeToken:text.
          op:equals("-"):ifElse({ negateNode:value(self:term) }, { self:term }) },
        { self:term }).
    { self:atOneOf("+-") }:whileTrue({
        op := self:takeToken:text.
        left := binaryNode:value(op, left, self:term) }).
    left }.

basic:term := { | left, op |
    left := self:factor.
    { self:atOneOf("*/") }:whileTrue({
        op := self:takeToken:text.
        left := binaryNode:value(op, left, self:factor) }).
    left }.

basic:factor := { | left |
    left := self:primary.
    { self:atOneOf("^") }:whileTrue({
        self:takeToken.
        left := binaryNode:value("^", left, self:primary) }).
    left }.

basic:primary := { | t, inner |
    t := self:takeToken.
    t:kind:equals('number):ifElse({ numberNode:value(t:text:asFloat) }, {
    t:kind:equals('string):ifElse({ stringNode:value(t:text) }, {
    t:kind:equals('word):ifElse({ variableNode:value(self:variableName(t)) }, {
    t:text:equals("("):ifElse({
        inner := self:expression.
        self:atOneOf(")"):ifFalse({ self:fail("a ( was never closed") }).
        self:takeToken.
        inner },
        { self:fail("'{}' cannot start a value":fill([t:text])) }) }) }) }) }.

; ---------------------------------------------------------------------------
; Evaluating
;
; And here the staircase wins, which is the third answer to the same question
; and not an inconsistency.
;
; **This is the recursive half.** It runs once per node of the tree, and
; anything that costs a frame here costs it at every level -- which is the cost
; `manifest.sol` measured, 124 levels of JSON becoming 18 once its value
; dispatch went through a dictionary of blocks. [control.sol](../lib/control.sol)
; says the same thing about `ifElseIf` in so many words: *use it for a flat
; dispatch and not inside a recursion*, three frames a level, 254 becoming 84.
;
; **Measured in this program rather than taken on trust.** A listing nests as
; deep as its brackets, and the deepest one this reads is 60 -- see the
; demonstration at the bottom. Written with `ifElseIf` in `primary` instead of a
; staircase, the same measurement gives **39**. A third of the depth, for four
; lines that read better.
;
; A staircase four deep is legible. Nineteen would not be, which is why the
; statement dispatch is a dictionary and this is not.

basic:evaluate := { n |
    n:kind:equals('number):ifElse({ n:value }, {
    n:kind:equals('string):ifElse({ n:value }, {
    n:kind:equals('variable):ifElse({ self:variable(n:name) }, {
    n:kind:equals('negate):ifElse({ 0.0:sub(self:numeric(self:evaluate(n:left))) }, {
        self:combine(n) }) }) }) }) }.

; **Every numeric variable starts at zero and none has to be declared.** That is
; the standard, and it is the opposite of what this language does one level
; down, where a name that was never bound is an error and
; [examples/strictness.sol](../examples/strictness.sol) explains at length why.
; Both are right for their own language: Solum is written by somebody who can
; spell the name again, and a BASIC listing was typed at a terminal that could
; not go back.
basic:variable := { name |
    self:vars:includes(name):ifElse({ self:vars:at(name) }, { 0.0 }) }.

; The two types do not mix, and the check is here rather than at each operator
; so that the message names the value rather than the machinery.
basic:numeric := { v |
    v:isKindOf(float):ifFalse({
        self:fail("expected a number, got the string \"{}\"":fill([v])) }).
    v }.

basic:combine := { n | | l, r, op |
    l := self:numeric(self:evaluate(n:left)).
    r := self:numeric(self:evaluate(n:right)).
    op := n:op.
    op:equals("+"):ifElse({ l:add(r) }, {
    op:equals("-"):ifElse({ l:sub(r) }, {
    op:equals("*"):ifElse({ l:mul(r) }, {
    op:equals("/"):ifElse({ l:div(r) }, {

    ; -----------------------------------------------------------------------
    ; And here is the finding this program was written to produce
    ;
    ; `^` is in the language being interpreted, and it cannot be implemented.
    ; Solum has no `pow`, and the ways round it are all wrong:
    ;
    ;   * repeated multiplication answers integer exponents only, and BASIC's
    ;     `^` takes any number -- `2^0.5` is the square root of two;
    ;   * `exp(y * log x)` needs two more functions this language also lacks.
    ;
    ; It is not stubbed with something plausible, because that is exactly the
    ; failure [3.14](../docs/ROADMAP.md#314-the-mathematics-that-is-not-here)
    ; already records twice: a hand-written `sqrt` wrong in the fourth digit,
    ; and a second one wrong by nineteen orders of magnitude, both silent. An
    ; operator that is right for `2^3` and quietly wrong for `2^0.5` would be
    ; the third.
    ;
    ; So it says what is missing, and the last demonstration below shows it
    ; saying so. Six of Minimal BASIC's eleven supplied functions -- SIN, COS,
    ; TAN, ATN, EXP and LOG -- are the same entry, and stage three cannot start
    ; until it is decided.
    op:equals("^"):ifElse({
        self:fail("^ needs 'pow', which this language does not have (ROADMAP 3.14)") }, {
        self:fail("'{}' is not an operator":fill([op])) }) }) }) }) }) }.

; ---------------------------------------------------------------------------
; Running
;
; The loop is left four ways -- `END`, the last line, an error, and `STOP` when
; stage two adds it -- and only one of them is running out of lines. So it
; carries `running`, a boolean whose entire job is to stop it, which is the
; shape [3.13](../docs/ROADMAP.md#313-a-loop-is-left-by-its-condition-or-by-failing)
; counts.

runners := dictionary:new.

runners:atPut('rem, { m, st | nil }).

runners:atPut('let, { m, st |
    m:vars:atPut(st:name, m:numeric(m:evaluate(st:expr))) }).

runners:atPut('end, { m, st | m:running := false }).

; Not called `print`, although that is the name of the statement: `print` is a
; message every object in this language already answers, and an interpreter that
; overrides it on itself would make `basic:print` mean one thing to a BASIC
; listing and another to anything that ever tried to look at the machine.
runners:atPut('print, { m, st | m:doPrint(st) }).

basic:run := { source |
    self:load(source).
    self:running := true.
    self:pc := #1.
    { self:running:and({ self:pc:lessOrEqual(self:order:size) }) }:whileTrue({
        self:atLine := self:order:at(self:pc).
        self:execute(self:lines:at(self:atLine)).
        self:pc := self:pc:add(#1) }).
    self:flushPending }.

basic:execute := { st |
    runners:includes(st:kind):ifFalse({
        self:fail("cannot run a {}":fill([st:kind])) }).
    runners:at(st:kind):value(self, st) }.

; ---------------------------------------------------------------------------
; What PRINT actually prints
;
; This is the part of BASIC that everyone remembers wrongly. `PRINT 14` does not
; print `14`; it prints a space, then `14`, then another space, because a number
; is written as a **sign character** -- a minus, or a space when it is not
; negative -- followed by the digits and then a trailing space. That is why
; BASIC output has its airy look, and why a negative number lines up under a
; positive one.
;
; A string is written exactly as it is, with no padding on either side.
;
; **The whole line is buffered rather than written a piece at a time**, because
; the only way this language has to put text on the terminal is `display`, which
; ends a line. That is not a complaint yet -- `PRINT` builds a line and then
; ends it, which buffering models exactly -- but it becomes one at stage four,
; where `INPUT "NAME"; N$` has to show a prompt and then read the answer from
; the same line, and nothing here can do that.

basic:zone := #15.         ; the width of a print zone; the standard leaves it open

basic:doPrint := { st | | last |
    st:items:size:equals(#0):ifElse({ self:flush }, {
        st:items:do({ item |
            item:expr:isNil:ifFalse({ self:emit(self:evaluate(item:expr)) }).
            item:sep:equals('comma):ifTrue({ self:tab }) }).
        last := st:items:at(st:items:size).
        last:sep:equals('none):ifTrue({ self:flush }) }) }.

basic:emit := { v |
    self:out := v:isKindOf(float):ifElse(
        { self:out:concat(self:formatted(v)) },
        { self:out:concat(v) }) }.

basic:formatted := { v |
    v:lessThan(0.0):ifElse(
        { v:asString:concat(" ") },
        { " ":concat(v:asString):concat(" ") }) }.

basic:tab := { | target |
    target := self:out:size:div(self:zone):add(#1):mul(self:zone).
    { self:out:size:lessThan(target) }:whileTrue({
        self:out := self:out:concat(" ") }) }.

; `PRINT` with nothing after it prints a blank line, so ending the line is
; unconditional here and the emptiness of the buffer is not a reason to skip it.
basic:flush := {
    self:out:display.
    self:out := "" }.

; At the end of a run it is the other way round. A line held open by a trailing
; `;` or `,` is still owed to the terminal, and a listing that ended its own
; last line owes nothing -- so this is the one place the buffer being empty
; means there is nothing to do. Flushing unconditionally here put a blank line
; after every listing, which is the kind of thing that looks like formatting
; until you count the lines.
basic:flushPending := {
    self:out:equals(""):ifFalse({ self:flush }) }.

; ---------------------------------------------------------------------------
; Running one, and reporting what went wrong
;
; A listing is written here as an array of lines rather than as one string with
; newlines in it, so that a listing on the page looks like a listing. Stage five
; reads the same text out of a `.bas` file and hands it to the same `run`.

listing := { lines |
    { basic:new:run(lines:join("\n")) }:onError({ e | e:message:display }) }.


; ---------------------------------------------------------------------------
; It runs a program

listing:value([
    "10 REM the smallest program that is one",
    "20 PRINT \"HELLO, WORLD\"",
    "30 END"]).
;   HELLO, WORLD

; ---------------------------------------------------------------------------
; It does arithmetic, and prints it the way BASIC does
;
; The spaces are the point. Every number goes out with a sign character in front
; of it and a space behind, so each line below begins with a space that is easy
; to mistake for indentation and is not.

listing:value([
    "10 PRINT 2 + 3 * 4",
    "20 PRINT (2 + 3) * 4",
    "30 PRINT 10 / 4",
    "40 PRINT -7",
    "50 END"]).
;    14
;    20
;    2.5
;   -7

; ---------------------------------------------------------------------------
; Where the standard's grammar shows through
;
; A sign belongs at the front of an expression and nowhere inside one, so the
; second of these is not a BASIC expression at all. Every dialect after 1978
; relaxed that, which is why the refusal reads like a bug in the interpreter
; rather than like the standard being kept.

listing:value(["10 PRINT -2 * 3", "20 END"]).
;   -6
listing:value(["10 PRINT 2 * -3", "20 END"]).
;   line 10: '-' cannot start a value

; Operators of equal precedence group to the left. That is unremarkable for `-`
; and `/`, and it is the surprise for `^`, where it makes `2^3^2` 64 here and
; 512 in almost every BASIC since.

listing:value(["10 PRINT 1 - 2 - 3", "20 END"]).
;   -4
listing:value(["10 PRINT 100 / 10 / 2", "20 END"]).
;    5

; ---------------------------------------------------------------------------
; Variables, which start at zero and are never declared

listing:value([
    "10 LET A = 6",
    "20 LET B = 7",
    "30 LET C = A * B",
    "40 PRINT C",
    "50 PRINT Z",
    "60 END"]).
;    42
;    0

; ---------------------------------------------------------------------------
; The separators
;
; `,` moves to the next fifteen-column zone and `;` moves nowhere, and either at
; the end of a line holds it open for the next `PRINT` to carry on.

listing:value([
    "10 PRINT \"A\", \"B\", \"C\"",
    "20 PRINT 1; 2; 3",
    "30 PRINT \"COUNT: \";",
    "40 PRINT 99",
    "50 END"]).
;   A              B              C
;    1  2  3
;   COUNT:  99

; ---------------------------------------------------------------------------
; The lines run in the order of their numbers, not the order they were typed

listing:value([
    "30 PRINT \"THIRD\"",
    "10 PRINT \"FIRST\"",
    "20 PRINT \"SECOND\"",
    "40 END"]).
;   FIRST
;   SECOND
;   THIRD

; ---------------------------------------------------------------------------
; It says where a listing is wrong
;
; Each of these is reported and the interpreter carries on, the way
; [evaluator.sol](evaluator.sol) does: a bad listing is input, not a fault.

listing:value(["10 PRINT (1 + 2", "20 END"]).
;   line 10: a ( was never closed
listing:value(["10 LET 3 = 4", "20 END"]).
;   line 10: '3' is not a variable
listing:value(["10 LET TOTAL = 1", "20 END"]).
;   line 10: 'TOTAL' is not a variable: a letter, or a letter and a digit
listing:value(["PRINT 1"]).
;   line 0: a line must start with a line number: PRINT 1
listing:value(["10 PRINT 1", "10 PRINT 2"]).
;   line 10: line 10 appears twice
listing:value(["10 GOTO 20", "20 END"]).
;   line 10: 'GOTO' is not a statement this understands yet
listing:value(["10 PRINT \"A\" + 1", "20 END"]).
;   line 10: expected a number, got the string "A"

; ---------------------------------------------------------------------------
; How deep a listing can nest
;
; The measurement the two dispatch comments above refer to, run rather than
; asserted. A bracket costs four frames -- `expression`, `term`, `factor`,
; `primary` -- so 254 frames is 60 of them.
;
; What makes this a footnote here and a finding in
; [evaluator.sol](evaluator.sol) is that it is paid **once, at load**. A BASIC
; program that loops a million times parses its expressions once and then walks
; the objects, so this bounds how baroque a single line may be and has nothing
; to say about how long a program may run. That is the whole of what line
; numbers buy.

deep := { n | | text |
    text := "10 PRINT ".
    n:repeat({ text := text:concat("(") }).
    text := text:concat("1+2").
    n:repeat({ text := text:concat(")") }).
    [text, "20 END"] }.

listing:value(deep:value(#60)).
;    3
listing:value(deep:value(#61)).
;   call depth exceeded

; Running out of frames arrives at `onError` like any other failure and the
; interpreter carries on, which is what makes it a limit rather than a crash --
; the same thing `evaluator.sol` found, on the same machine, for the same
; reason.

; ---------------------------------------------------------------------------
; And the one it cannot run
;
; `^` is in the language and is not in this one. ROADMAP 3.14 has been waiting
; for a program that wants an angle; this is a program that wants six of them
; and an exponent operator besides, and it cannot be finished without them.

listing:value([
    "10 PRINT 2 ^ 3",
    "20 END"]).
;   line 10: ^ needs 'pow', which this language does not have (ROADMAP 3.14)
