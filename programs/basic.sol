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
; is small enough to finish: twenty statements and eleven supplied functions.
;
; ---------------------------------------------------------------------------
; What is here so far
;
; **All twenty statements of the standard are here.**
;
;   one   `LET`, `PRINT`, `REM`, `END`, and the whole numeric expression
;         grammar. The tokeniser, the expression parser and its tree, the line
;         table, the run loop and its program counter, and `PRINT`'s output
;         rules -- which are stranger than they look, and are why the
;         demonstrations at the bottom have spaces in them where you would not
;         expect any.
;
;   two   `GOTO`, `IF-THEN`, `FOR/NEXT`, `GOSUB/RETURN`, `ON-GOTO` and `STOP`.
;         Three passes over the listing at load, so that a jump is an array
;         index rather than a search, a jump to a line that does not exist is
;         reported before anything runs, and a `FOR` knows where its `NEXT` is.
;         It runs about 420,000 BASIC statements a second.
;
;   four  Text, arrays, `DIM`, `OPTION BASE`, `DATA`/`READ`/`RESTORE`, `INPUT`,
;         `DEF FN`, `RANDOMIZE`, and five of the eleven supplied functions. A
;         fourth pass at load, because `DATA`, `DEF` and `OPTION BASE` are all
;         in force for the whole listing wherever they are written.
;
;   three All eleven supplied functions and the `^` operator. Six of them and
;         the operator waited two days on
;         [3.14](../docs/COMPLETED.md#314-the-mathematics-that-is-not-here--done),
;         an entry that had been waiting since it was written for a program
;         that wanted an angle. This was that program, and it wanted six.
;
; **The language is complete**: twenty statements, eleven functions, and every
; rule of the standard this file has found a way to check. What is left is
; stage five -- the rest of `PRINT`'s formatting, and a recorded transcript for
; each listing in [basic/](basic/) rather than the claims in comments used here.
;
; Stage four went ahead of stage three because it turned out not to depend on
; it, and then took part of it anyway: `A(1)` and `ABS(1)` are the same syntax,
; so arrays could not be built without the machinery that calls a function.
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
node:kind := 'number.      ; 'number 'string 'variable 'binary 'negate 'index 'call
node:value := nil.         ; 'number, 'string
node:name := "".           ; 'variable, 'index, 'call
node:op := "".             ; 'binary
node:left := nil.
node:right := nil.
node:args := nil.          ; 'index (the subscripts), 'call (the arguments)

numberNode := { v | | n | n := node:new. n:kind := 'number. n:value := v. n }.
stringNode := { v | | n | n := node:new. n:kind := 'string. n:value := v. n }.
variableNode := { name | | n | n := node:new. n:kind := 'variable. n:name := name. n }.
binaryNode := { op, l, r | | n |
    n := node:new. n:kind := 'binary. n:op := op. n:left := l. n:right := r. n }.
negateNode := { x | | n | n := node:new. n:kind := 'negate. n:left := x. n }.
indexNode := { name, args | | n |
    n := node:new. n:kind := 'index. n:name := name. n:args := args. n }.
callNode := { name, args | | n |
    n := node:new. n:kind := 'call. n:name := name. n:args := args. n }.

; ---------------------------------------------------------------------------
; An array
;
; The cells are one flat array whatever the rank, with the subscripts folded
; into an index -- which is what `dims` is kept for. Two dimensions is the most
; Minimal BASIC allows.

arrayValue := object:new.
arrayValue:dims := nil.    ; the upper bound of each subscript
arrayValue:cells := nil.

; ---------------------------------------------------------------------------
; Statements
;
; A statement is parsed once, at load, into one of these. The run loop then
; walks the objects rather than the text, which is not an optimisation so much
; as the difference between an interpreter and a toy: a `FOR` loop in stage two
; will run its body tens of thousands of times, and re-reading the characters
; each pass would make the cost of the loop the cost of parsing it.

statement := object:new.
statement:kind := 'rem.    ; 'rem 'let 'print 'end 'goto 'gosub 'return
                           ; 'if 'for 'next 'ongoto 'stop
statement:name := "".      ; 'let, 'for, 'next
statement:expr := nil.     ; 'let, 'for (the initial value), 'ongoto
statement:items := nil.    ; 'print
statement:left := nil.     ; 'if
statement:op := "".        ; 'if
statement:right := nil.    ; 'if
statement:limit := nil.    ; 'for
statement:step := nil.     ; 'for, nil when none was written
statement:pair := #0.      ; 'for and 'next: each other's place in the run order
statement:target := nil.   ; 'let: the variable or array element assigned to

; **Line numbers written in a statement, and where they landed.** A `GOTO` says
; a line number and the run loop wants an index into `order`, so the lookup
; happens once at load rather than once per jump -- which matters because the
; jumps in a BASIC program are the loop. `targets` is what the listing said and
; `resolved` is where it points; a target that names no line is caught at load,
; where it can be reported before anything has run.
statement:targets := nil.
statement:resolved := nil.

; A `FOR` in flight: the control variable, where the body starts, and the limit
; and step as they were **when the loop began**. Evaluating them once is the
; standard's rule and not an optimisation -- `FOR I = 1 TO N` where the body
; assigns to `N` runs the number of times `N` named at the start.
loopFrame := object:new.
loopFrame:name := "".
loopFrame:limit := 0.0.
loopFrame:step := 1.0.
loopFrame:body := #1.

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
basic:index := nil.        ; line number -> its place in `order`
basic:jumped := false.     ; whether the statement just run moved the counter
basic:calls := nil.        ; GOSUB return places, innermost last
basic:loops := nil.        ; FOR frames, innermost last
basic:arrays := nil.       ; name -> arrayValue
basic:defined := nil.      ; FNx -> the DEF statement that defines it
basic:data := nil.         ; every DATA value in the listing, in line order
basic:dataAt := #1.        ; how far READ has got through it
basic:rng := nil.          ; RND's generator; RANDOMIZE replaces it
basic:base := #0.          ; the lowest subscript, which OPTION BASE sets

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
basic:wordToken := { s | | text |
    text := s:takeWhile({ c | isLetter:value(c):or({ isDigit:value(c) }) }):asUppercase.
    ; The `$` is part of the name and not an operator: `A$` is one variable and
    ; the dollar is how its type is spelt. Minimal BASIC has exactly two types
    ; and no way to declare either, so the name carries it.
    makeToken:value('word, s:match("$"):ifElse({ text:concat("$") }, { text })) }.

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
    self:order := self:lines:keys:sorted.
    self:placeLines.
    self:resolveTargets.
    self:pairLoops.
    self:gather }.

; ---------------------------------------------------------------------------
; Three passes over the loaded listing, all of them at load
;
; A BASIC program is a graph and not a sequence, and the edges are line numbers.
; Every one of them is followed here before anything runs, which buys three
; things: a jump is an array index rather than a search, a `GOTO` to a line that
; does not exist is reported before the program prints anything, and a `FOR`
; with no `NEXT` is a listing error rather than a surprise at run time.

basic:placeLines := {
    self:index := dictionary:new.
    [#1, self:order:size]:loop({ i |
        self:index:atPut(self:order:at(i), i) }) }.

; Without this a jump would be `order:indexOf(line)`, a scan of the whole
; listing -- and the jumps in a BASIC program are its loops, so the scan would
; be per iteration. It is the one place where an interpreter for a language with
; line numbers has to do something a tree-walking one never would.
basic:resolveTargets := {
    self:order:do({ line | | st |
        st := self:lines:at(line).
        st:targets:isNil:ifFalse({
            self:atLine := line.
            st:resolved := st:targets:collect({ n |
                self:index:includes(n):ifFalse({
                    self:fail("there is no line {}":fill([n])) }).
                self:index:at(n) }) }) }) }.

; `FOR` and `NEXT` find each other here rather than at run time, which needs
; them properly nested -- and the standard requires that, so following it is
; free. The pairing is what lets a `FOR` whose range is empty skip its body: it
; already knows where the body ends.
; `DATA` and `DEF` are both in force for the whole listing regardless of where
; they are written, so both are collected before anything runs. One walk does
; the two of them because they are the same walk, not because they are related.
basic:gather := { | dimmed, based |
    self:data := array:new.
    self:defined := dictionary:new.
    self:base := #0.
    dimmed := false.
    based := false.
    self:order:do({ line | | st |
        st := self:lines:at(line).
        self:atLine := line.
        st:kind:equals('data):ifTrue({
            st:items:do({ v | self:data:add(v) }) }).
        st:kind:equals('dim):ifTrue({ dimmed := true }).
        st:kind:equals('option):ifTrue({
            based:ifTrue({ self:fail("OPTION BASE is said twice") }).
            dimmed:ifTrue({
                self:fail("OPTION BASE comes before any DIM, not after") }).
            based := true.
            self:base := st:pair }).
        st:kind:equals('def):ifTrue({
            self:defined:includes(st:name):ifTrue({
                self:fail("{} is defined twice":fill([st:name])) }).
            self:defined:atPut(st:name, st) }) }).
    self:dataAt := #1 }.

basic:pairLoops := { | stack, st, opening |
    stack := array:new.
    [#1, self:order:size]:loop({ i |
        st := self:lines:at(self:order:at(i)).
        self:atLine := self:order:at(i).
        st:kind:equals('for):ifTrue({ stack:add(i) }).
        st:kind:equals('next):ifTrue({
            stack:size:equals(#0):ifTrue({ self:fail("NEXT without a FOR") }).
            opening := stack:at(stack:size).
            stack:removeLast.
            self:lines:at(self:order:at(opening)):name:equals(st:name):ifFalse({
                self:fail("NEXT {} closes FOR {}"
                    :fill([st:name, self:lines:at(self:order:at(opening)):name])) }).
            self:lines:at(self:order:at(opening)):pair := i.
            st:pair := opening }) }).
    stack:size:equals(#0):ifFalse({
        self:atLine := self:order:at(stack:at(stack:size)).
        self:fail("FOR without a NEXT") }) }.

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
; A **staircase of `ifElse`** is out because there are twenty statements to
; recognise and [3.2](../docs/ROADMAP.md#32-no-non-local-return) gives no early
; return to leave a chain from, so it would be twenty levels deep and a wall of
; brackets at the end.
;
; **[ifElseIf](../lib/control.sol)** is the library's answer to exactly that,
; and it is the right shape for a flat dispatch -- the tokeniser below uses it.
; It is the wrong shape *here* because it tests its conditions in order: with
; twenty keywords, recognising `STOP` means twenty block calls and twenty
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
            tokens := self:joinGo(tokens).
            keyword := tokens:at(#1).
            keyword:kind:equals('word):ifFalse({
                self:fail("a statement starts with a keyword, not '{}'"
                    :fill([keyword:text])) }).
            parsers:includes(keyword:text):ifFalse({
                self:fail("'{}' is not a statement in Minimal BASIC"
                    :fill([keyword:text])) }).
            parsers:at(keyword:text):value(self, tokens) }) }.

basic:statementOf := { kind | | st |
    st := statement:new. st:kind := kind. st }.

; ECMA-55 requires the word `LET`. Later BASICs made it optional and this one
; does not, because the standard is the whole reason for having chosen a dialect
; and the first convenience is the one that makes the second hard to refuse.
parsers:atPut("LET", { m, tokens | | st, target |
    tokens:size:lessThan(#4):ifTrue({
        m:fail("LET needs a variable, an = and a value") }).
    st := m:statementOf('let).

    ; The left side is parsed by the ordinary expression machinery and then
    ; checked, rather than being read by hand -- `A`, `A$` and `A(I,J)` are
    ; already three shapes and `primary` knows all of them. `=` is not an
    ; operator in this grammar, so the parse stops exactly where it should.
    target := m:parse(tokens, #2).
    target:kind:equals('variable):or({ target:kind:equals('index) }):ifFalse({
        m:fail("LET assigns to a variable or an array element") }).
    st:target := target.
    m:expect(tokens, m:cursor, "=", "LET needs an = after the variable").
    st:expr := m:parse(tokens, m:cursor:add(#1)).
    st }).

parsers:atPut("END", { m, tokens |
    tokens:size:equals(#1):ifFalse({ m:fail("END takes nothing after it") }).
    m:statementOf('end) }).

; `STOP` and `END` do the same thing here. The standard distinguishes them by
; where they may appear -- `END` is the last line of the program and there is
; exactly one -- and this does not enforce that, because a listing typed to try
; something out is not improved by being told it has no `END`.
parsers:atPut("STOP", { m, tokens |
    tokens:size:equals(#1):ifFalse({ m:fail("STOP takes nothing after it") }).
    m:statementOf('stop) }).

; ---------------------------------------------------------------------------
; GO TO, which is two words
;
; The standard writes `GO TO` and `GO SUB` with a space, because spaces are not
; significant in Minimal BASIC and the two spellings are the same statement.
; This tokeniser splits on spaces, so it sees either one word or two, and the
; two are put back together here -- before the keyword table is asked, so the
; table has one entry per statement rather than two.

basic:joinGo := { tokens | | rest |
    tokens:at(#1):text:equals("GO"):and({ tokens:size:greaterThan(#1) })
        :and({ tokens:at(#2):text:equals("TO"):or({
                   tokens:at(#2):text:equals("SUB") }) })
        :ifElse({
            rest := array:of(makeToken:value('word,
                "GO":concat(tokens:at(#2):text))).
            [#3, tokens:size]:loop({ i | rest:add(tokens:at(i)) }).
            rest },
            { tokens }) }.

; A line number is a whole number and nothing else. `10.5` tokenises as a
; perfectly good numeric literal, which is why this is checked rather than
; assumed: `GOTO 10.5` should say what is wrong with it and not round.
basic:lineNumber := { t | self:wholeNumber(t, "a line number") }.

basic:tokenAt := { tokens, i |
    i:greaterThan(tokens:size):ifElse({ nil }, { tokens:at(i) }) }.

basic:expect := { tokens, i, text, message | | t |
    t := self:tokenAt(tokens, i).
    t:isNil:or({ t:text:equals(text):not }):ifTrue({ self:fail(message) }).
    t }.

; A whole number written out, which `DIM` and every line number need and which
; the tokeniser will happily have read as `10.5` or `1E3`.
basic:wholeNumber := { t, what |
    t:isNil:ifTrue({ self:fail("{} is missing":fill([what])) }).
    t:kind:equals('number)
        :and({ t:text:indexOf("."):isNil })
        :and({ t:text:asUppercase:indexOf("E"):isNil })
        :ifFalse({ self:fail("'{}' is not {}":fill([t:text, what])) }).
    t:text:asInteger }.

parsers:atPut("GOTO", { m, tokens | | st |
    tokens:size:equals(#2):ifFalse({ m:fail("GOTO takes one line number") }).
    st := m:statementOf('goto).
    st:targets := [m:lineNumber(tokens:at(#2))].
    st }).

parsers:atPut("GOSUB", { m, tokens | | st |
    tokens:size:equals(#2):ifFalse({ m:fail("GOSUB takes one line number") }).
    st := m:statementOf('gosub).
    st:targets := [m:lineNumber(tokens:at(#2))].
    st }).

parsers:atPut("RETURN", { m, tokens |
    tokens:size:equals(#1):ifFalse({ m:fail("RETURN takes nothing after it") }).
    m:statementOf('return) }).

; ---------------------------------------------------------------------------
; IF, which in this dialect can only jump
;
;     IF <expression> <relation> <expression> THEN <line number>
;
; **`THEN` takes a line number and not a statement.** `IF X > 0 THEN PRINT "YES"`
; is not Minimal BASIC; it is `IF X > 0 THEN 100`, with the work on line 100 and
; a `GOTO` round it. Every dialect after this one allowed the statement form,
; which is why the restriction reads like a missing feature rather than the
; standard being kept -- the same shape as the sign rule in the expression
; grammar, and refused for the same reason.

relations := ["=", "<>", "<", "<=", ">", ">="].

parsers:atPut("IF", { m, tokens | | st, t |
    st := m:statementOf('if).
    st:left := m:parse(tokens, #2).

    t := m:tokenAt(tokens, m:cursor).
    t:isNil:ifTrue({ m:fail("IF needs a comparison") }).
    relations:indexOf(t:text):isNil:ifTrue({
        m:fail("'{}' is not a comparison: one of = <> < <= > >=":fill([t:text])) }).
    st:op := t:text.
    st:right := m:parse(tokens, m:cursor:add(#1)).

    t := m:tokenAt(tokens, m:cursor).
    t:isNil:or({ t:text:equals("THEN"):not }):ifTrue({
        m:fail("IF needs THEN and a line number") }).
    t := m:tokenAt(tokens, m:cursor:add(#1)).
    t:isNil:ifTrue({ m:fail("THEN needs a line number") }).
    ; Named rather than left to `lineNumber`, because the mistake here is
    ; almost never a mistyped number -- it is knowing a later BASIC.
    t:kind:equals('word):ifTrue({
        m:fail("THEN takes a line number in this dialect, not a statement: "
               :concat("put the {} on its own line and jump to it")
               :fill([t:text])) }).
    st:targets := [m:lineNumber(t)].
    m:cursor:add(#2):lessOrEqual(tokens:size):ifTrue({
        m:fail("THEN takes a line number and nothing after it") }).
    st }).

; ---------------------------------------------------------------------------
; ON ... GOTO -- the computed jump
;
;     ON <expression> GOTO <line>, <line>, ...
;
; The value picks a line by its position in the list, counting from one. Out of
; range is an error rather than a fall-through, which is the standard's reading
; and the useful one: a computed jump that quietly does nothing is a bug that
; looks like a working program.

parsers:atPut("ON", { m, tokens | | st, t, i |
    st := m:statementOf('ongoto).
    st:expr := m:parse(tokens, #2).
    t := m:tokenAt(tokens, m:cursor).
    t:isNil:or({ t:text:equals("GOTO"):not }):ifTrue({
        m:fail("ON needs GOTO and a list of line numbers") }).
    st:targets := array:new.
    i := m:cursor:add(#1).
    { i:lessOrEqual(tokens:size) }:whileTrue({
        st:targets:add(m:lineNumber(tokens:at(i))).
        i := i:add(#1).
        i:lessOrEqual(tokens:size):ifTrue({
            tokens:at(i):text:equals(","):ifFalse({
                m:fail("line numbers after GOTO are separated by commas") }).
            i := i:add(#1).
            i:greaterThan(tokens:size):ifTrue({
                m:fail("a comma with no line number after it") }) }) }).
    st:targets:size:equals(#0):ifTrue({ m:fail("ON GOTO needs a line number") }).
    st }).

; ---------------------------------------------------------------------------
; FOR and NEXT
;
;     FOR <variable> = <expression> TO <expression> [STEP <expression>]
;     NEXT <variable>
;
; The limit and the step are evaluated **once, when the loop starts**, which is
; the standard's rule rather than an optimisation: `FOR I = 1 TO N` where the
; body assigns to `N` runs the number of times `N` named at the start. The test
; happens before the body, so a loop whose range is already empty runs no times.

parsers:atPut("FOR", { m, tokens | | st, t |
    st := m:statementOf('for).
    st:name := m:numericName(m:tokenAt(tokens, #2)).
    t := m:tokenAt(tokens, #3).
    t:isNil:or({ t:text:equals("=") :not }):ifTrue({
        m:fail("FOR needs an = after the variable") }).
    st:expr := m:parse(tokens, #4).

    t := m:tokenAt(tokens, m:cursor).
    t:isNil:or({ t:text:equals("TO"):not }):ifTrue({ m:fail("FOR needs TO") }).
    st:limit := m:parse(tokens, m:cursor:add(#1)).

    t := m:tokenAt(tokens, m:cursor).
    t:isNil:ifElse({ st:step := nil }, {
        t:text:equals("STEP"):ifFalse({
            m:fail("FOR takes STEP and nothing else after the limit") }).
        st:step := m:parse(tokens, m:cursor:add(#1)).
        m:cursor:lessOrEqual(tokens:size):ifTrue({
            m:fail("STEP takes one value") }) }).
    st }).

parsers:atPut("NEXT", { m, tokens | | st |
    tokens:size:equals(#2):ifFalse({ m:fail("NEXT takes one variable") }).
    st := m:statementOf('next).
    st:name := m:numericName(tokens:at(#2)).
    st }).

; ---------------------------------------------------------------------------
; DIM
;
;     DIM A(10), B(3,3)
;
; The bounds are written-out whole numbers and not expressions, which is the
; standard: an array's size is a property of the listing rather than of the run,
; so it can be read off the page.

parsers:atPut("DIM", { m, tokens | | st, i, name, dims |
    st := m:statementOf('dim).
    st:items := array:new.
    i := #2.
    { i:lessOrEqual(tokens:size) }:whileTrue({
        name := m:arrayName(m:variableName(m:tokenAt(tokens, i))).
        i := i:add(#1).
        m:expect(tokens, i, "(",
            "DIM needs a bound in brackets after {}":fill([name])).
        i := i:add(#1).
        dims := array:new.
        dims:add(m:wholeNumber(m:tokenAt(tokens, i), "a bound")).
        i := i:add(#1).
        { m:tokenAt(tokens, i):notNil
            :and({ m:tokenAt(tokens, i):text:equals(",") }) }:whileTrue({
            i := i:add(#1).
            dims:add(m:wholeNumber(m:tokenAt(tokens, i), "a bound")).
            i := i:add(#1) }).
        dims:size:greaterThan(#2):ifTrue({
            m:fail("{} has {} subscripts, and this dialect allows two"
                :fill([name, dims:size])) }).
        m:expect(tokens, i, ")", "DIM: a ( was never closed").
        i := i:add(#1).
        st:items:add([name, dims]).
        m:tokenAt(tokens, i):notNil:ifTrue({
            m:expect(tokens, i, ",", "DIM separates arrays with commas").
            i := i:add(#1).
            m:tokenAt(tokens, i):isNil:ifTrue({
                m:fail("DIM: a comma with nothing after it") }) }) }).
    st:items:size:equals(#0):ifTrue({ m:fail("DIM needs an array") }).
    st }).

; ---------------------------------------------------------------------------
; DEF, which defines one function of one number
;
;     DEF FNS(X) = X * X
;
; Not a statement that runs: the definition is in force for the whole listing
; however far down it is written, so these are collected at load with the DATA
; and the run loop steps over them.

parsers:atPut("DEF", { m, tokens | | st, name |
    st := m:statementOf('def).
    name := m:tokenAt(tokens, #2).
    name:isNil:or({ name:kind:equals('word):not }):ifTrue({
        m:fail("DEF needs a name like FNA") }).
    name:text:size:equals(#3)
        :and({ name:text:copyFrom(#1, #2):equals("FN") })
        :and({ isLetter:value(name:text:at(#3)) })
        :ifFalse({ m:fail("'{}' is not a function name: FN and one letter"
            :fill([name:text])) }).
    st:name := name:text.
    m:expect(tokens, #3, "(", "DEF needs a parameter in brackets").
    st:items := [m:numericName(m:tokenAt(tokens, #4))].
    m:expect(tokens, #5, ")", "DEF: a ( was never closed").
    m:expect(tokens, #6, "=", "DEF needs an = and then the expression").
    st:expr := m:parse(tokens, #7).
    m:cursor:lessOrEqual(tokens:size):ifTrue({
        m:fail("DEF takes one expression") }).
    st }).

; ---------------------------------------------------------------------------
; DATA, READ and RESTORE -- a listing's own input
;
; Every `DATA` in the program is one list, in line order, however the lines are
; scattered. `READ` walks it and `RESTORE` goes back to the beginning. It is the
; oldest way a program carried its own input, and it is why so much BASIC has a
; wall of numbers at the bottom.
;
; A `DATA` item is a constant and never an expression, so these are read here
; and not parsed into a tree. An unquoted word is text -- `DATA JANUARY` is the
; string, not a variable -- which is the standard and catches everybody once.

parsers:atPut("DATA", { m, tokens | | st, i, t, negate |
    st := m:statementOf('data).
    st:items := array:new.
    i := #2.
    { i:lessOrEqual(tokens:size) }:whileTrue({
        negate := false.
        m:tokenAt(tokens, i):text:equals("-"):ifTrue({
            negate := true. i := i:add(#1) }).
        t := m:tokenAt(tokens, i).
        t:isNil:ifTrue({ m:fail("DATA: a comma with nothing after it") }).
        t:kind:equals('number):ifElse(
            { st:items:add(negate:ifElse(
                  { 0.0:sub(t:text:asFloat) }, { t:text:asFloat })) },
            { negate:ifTrue({ m:fail("DATA: '-' before text") }).
              t:kind:equals('string):or({ t:kind:equals('word) }):ifElse(
                  { st:items:add(t:text) },
                  { m:fail("'{}' is not a DATA value":fill([t:text])) }) }).
        i := i:add(#1).
        m:tokenAt(tokens, i):notNil:ifTrue({
            m:expect(tokens, i, ",", "DATA separates values with commas").
            i := i:add(#1).
            m:tokenAt(tokens, i):isNil:ifTrue({
                m:fail("DATA: a comma with nothing after it") }) }) }).
    st:items:size:equals(#0):ifTrue({ m:fail("DATA needs a value") }).
    st }).

; `READ` and `INPUT` both fill in a list of places, so they share the reading of
; that list. The places are parsed as expressions and then checked, the same way
; `LET`'s left side is.
basic:places := { tokens, from | | out |
    out := array:new.
    out:add(self:place(self:parse(tokens, from))).
    { self:tokenAt(tokens, self:cursor):notNil
        :and({ self:tokenAt(tokens, self:cursor):text:equals(",") }) }:whileTrue({
        out:add(self:place(self:parse(tokens, self:cursor:add(#1)))) }).
    self:cursor:lessOrEqual(tokens:size):ifTrue({
        self:fail("'{}' is not a variable":fill([tokens:at(self:cursor):text])) }).
    out }.

basic:place := { node |
    node:kind:equals('variable):or({ node:kind:equals('index) }):ifFalse({
        self:fail("this needs a variable or an array element") }).
    node }.

parsers:atPut("READ", { m, tokens | | st |
    st := m:statementOf('read).
    st:items := m:places(tokens, #2).
    st }).

parsers:atPut("RESTORE", { m, tokens |
    tokens:size:equals(#1):ifFalse({ m:fail("RESTORE takes nothing after it") }).
    m:statementOf('restore) }).

parsers:atPut("INPUT", { m, tokens | | st |
    st := m:statementOf('input).
    st:items := m:places(tokens, #2).
    st }).

parsers:atPut("RANDOMIZE", { m, tokens |
    tokens:size:equals(#1):ifFalse({ m:fail("RANDOMIZE takes nothing after it") }).
    m:statementOf('randomize) }).

; ---------------------------------------------------------------------------
; OPTION BASE, the last statement in the standard
;
;     OPTION BASE 1
;
; Says whether subscripts start at nought or at one, for the whole program. Like
; `DEF` and `DATA` it is read at load and not run, and the standard allows one
; of them and requires it before any `DIM` -- both of which are checked, because
; an `OPTION` after the array it was meant to shape is the kind of mistake that
; changes every answer quietly.

parsers:atPut("OPTION", { m, tokens | | st |
    m:expect(tokens, #2, "BASE", "OPTION BASE is the only OPTION there is").
    st := m:statementOf('option).
    st:pair := m:wholeNumber(m:tokenAt(tokens, #3), "0 or 1").
    st:pair:equals(#0):or({ st:pair:equals(#1) }):ifFalse({
        m:fail("OPTION BASE takes 0 or 1, not {}":fill([st:pair])) }).
    tokens:size:equals(#3):ifFalse({ m:fail("OPTION BASE takes one number") }).
    st }).

; A numeric variable in Minimal BASIC is a letter, or a letter and one digit,
; and a string variable is a letter and a `$`. Two hundred and eighty-six of the
; first and twenty-six of the second, and that is the whole namespace -- so
; `TOTAL` is not a long variable name, it is five of them run together.

basic:isText := { name | name:at(name:size):equals("$") }.

basic:variableName := { t | | text, base |
    t:kind:equals('word):ifFalse({
        self:fail("'{}' is not a variable":fill([t:text])) }).
    text := t:text.
    base := self:isText(text):ifElse(
        { text:copyFrom(#1, text:size:sub(#1)) },
        { text }).
    self:isText(text):ifElse(
        { base:size:equals(#1):and({ isLetter:value(base) }) },
        { base:size:equals(#1):and({ isLetter:value(base) })
            :or({ base:size:equals(#2)
                    :and({ isLetter:value(base:at(#1)) })
                    :and({ isDigit:value(base:at(#2)) }) }) })
        :ifFalse({ self:fail(
            "'{}' is not a variable: a letter, a letter and a digit, or a letter and $"
                :fill([text])) }).
    text }.

; The places a name has to be a number: a loop counter, and the parameter of a
; `DEF`. Nothing in Minimal BASIC counts with text.
basic:numericName := { t | | name |
    name := self:variableName(t).
    self:isText(name):ifTrue({
        self:fail("{} holds text, and this needs a number":fill([name])) }).
    name }.

; An array is named by a single letter and there are no string arrays in this
; dialect, which is worth saying outright because `DIM N$(10)` is the first
; thing anybody tries.
basic:arrayName := { name |
    self:isText(name):ifTrue({
        self:fail("{} is text, and this dialect has no arrays of text"
            :fill([name])) }).
    name:size:equals(#1):and({ isLetter:value(name) }):ifFalse({
        self:fail("'{}' is not an array: an array is named by a single letter"
            :fill([name])) }).
    name }.

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
    t:kind:equals('word):ifElse({ self:nameOrCall(t) }, {
    t:text:equals("("):ifElse({
        inner := self:expression.
        self:atOneOf(")"):ifFalse({ self:fail("a ( was never closed") }).
        self:takeToken.
        inner },
        { self:fail("'{}' cannot start a value":fill([t:text])) }) }) }) }) }.

; ---------------------------------------------------------------------------
; A(1) is either an array or a function, and BASIC writes them the same
;
; **This is the reason stage four could not be done without most of stage
; three.** `A(1)` and `ABS(1)` are the same shape, and nothing in the grammar
; tells them apart -- a language with no keywords for its own library has
; nowhere to put the distinction except the name. So the name decides: one of
; the eleven supplied functions, or `FN` and a letter, is a call; a single
; letter is an array.
;
; A modern language would have made these different syntax and lost something
; for it. Fortran did the same thing in 1957 and for the same reason, and it is
; why the argument about whether `A(1)` should have meant a lookup either way
; is older than most languages.

basic:nameOrCall := { t | | name |
    name := t:text.
    self:atOneOf("("):ifElse(
        { self:applied(name, self:arguments) },
        { ; `RND` is the one function written with no brackets at all, which is
          ; the standard and the only reason this branch is not just a variable.
          name:equals("RND"):ifElse(
            { callNode:value("RND", array:new) },
            { variableNode:value(self:variableName(t)) }) }) }.

basic:applied := { name, args |
    functions:includes(name)
        :or({ self:looksLikeFn(name) })
        :ifElse(
            { callNode:value(name, args) },
            { indexNode:value(self:arrayName(name), args) }) }.

basic:looksLikeFn := { name |
    name:size:greaterOrEqual(#3):and({ name:copyFrom(#1, #2):equals("FN") }) }.

basic:arguments := { | args |
    self:takeToken.
    args := array:new.
    args:add(self:expression).
    { self:atOneOf(",") }:whileTrue({
        self:takeToken.
        args:add(self:expression) }).
    self:atOneOf(")"):ifFalse({ self:fail("a ( was never closed") }).
    self:takeToken.
    args }.

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
    n:kind:equals('variable):ifElse({ self:variable(n:name) }, {
    n:kind:equals('binary):ifElse({ self:combine(n) }, {
    n:kind:equals('index):ifElse({ self:element(n) }, {
    n:kind:equals('call):ifElse({ self:apply(n) }, {
    n:kind:equals('string):ifElse({ n:value }, {
        0.0:sub(self:numeric(self:evaluate(n:left))) }) }) }) }) }) }) }.

; The arms are in the order a running program meets them, which is not the order
; they were written in. A staircase tests from the top, so `number` and
; `variable` being first is worth the untidiness of `negate` -- the rarest kind
; in any listing -- falling off the bottom as the default.

; **Every numeric variable starts at zero and none has to be declared.** That is
; the standard, and it is the opposite of what this language does one level
; down, where a name that was never bound is an error and
; [examples/strictness.sol](../examples/strictness.sol) explains at length why.
; Both are right for their own language: Solum is written by somebody who can
; spell the name again, and a BASIC listing was typed at a terminal that could
; not go back.
basic:variable := { name |
    self:vars:includes(name):ifElse({ self:vars:at(name) },
        { self:isText(name):ifElse({ "" }, { 0.0 }) }) }.

; ---------------------------------------------------------------------------
; Assigning, which is where the two types are kept apart
;
; A name says which type it holds, so this is the only place a check is needed
; and it is a check about the name rather than about what was there before.

basic:assign := { target, value | | arr |
    target:kind:equals('variable):ifElse(
        { self:vars:atPut(target:name, self:fitting(target:name, value)) },
        { arr := self:arrayFor(target:name, target:args:size).
          arr:cells:atPut(self:cellAt(arr, target:args), self:numeric(value)) }) }.

basic:fitting := { name, value |
    self:isText(name):ifElse(
        { value:isKindOf(string):ifFalse({
              self:fail("{} holds text, and {} is a number":fill([name, value])) }).
          value },
        { self:numeric(value) }) }.

; ---------------------------------------------------------------------------
; Arrays
;
; Subscripts start at **zero**, which is the standard's default and the reason
; so much old BASIC has exactly eleven of things in it. An array used without
; `DIM` gets a bound of ten on every subscript, so `A(0)` to `A(10)` work with
; nothing declared -- also the standard, and the source of a great many
; off-by-one bugs that were never anybody's fault.

basic:makeArray := { name, dims | | v, cells |
    v := arrayValue:new.
    v:dims := dims.
    cells := #1.
    dims:do({ d |
        d:lessThan(self:base):ifTrue({
            self:fail("{} is given a bound of {}, below the base of {}"
                :fill([name, d, self:base])) }).
        cells := cells:mul(d:sub(self:base):add(#1)) }).
    v:cells := array:new.
    cells:repeat({ v:cells:add(0.0) }).
    self:arrays:atPut(name, v).
    v }.

basic:arrayFor := { name, rank | | dims |
    self:arrays:includes(name):ifFalse({
        dims := array:new.
        rank:repeat({ dims:add(#10) }).
        self:makeArray(name, dims) }).
    self:arrays:at(name) }.

; The subscripts are folded into one index, most significant first, so `A(I,J)`
; strides by the second bound. A subscript is rounded rather than truncated,
; which is the standard: `A(1.7)` is `A(2)`.
basic:cellAt := { arr, args | | at |
    args:size:equals(arr:dims:size):ifFalse({
        self:fail("this array has {} subscript(s) and was given {}"
            :fill([arr:dims:size, args:size])) }).
    at := #0.
    [#1, args:size]:loop({ k | | s |
        s := self:numeric(self:evaluate(args:at(k))):rounded.
        s:lessThan(self:base):or({ s:greaterThan(arr:dims:at(k)) }):ifTrue({
            self:fail("subscript {} is outside {} to {}"
                :fill([s, self:base, arr:dims:at(k)])) }).
        at := at:mul(arr:dims:at(k):sub(self:base):add(#1))
                 :add(s:sub(self:base)) }).
    at:add(#1) }.

basic:element := { n | | arr |
    arr := self:arrayFor(n:name, n:args:size).
    arr:cells:at(self:cellAt(arr, n:args)) }.

; ---------------------------------------------------------------------------
; The supplied functions, and the five that are here
;
; **All eleven of them, which is the whole language.** Five of these were here
; from the day arrays were, because `A(1)` and `ABS(1)` are the same syntax. The
; other six -- `SIN`, `COS`, `TAN`, `ATN`, `EXP` and `LOG` -- waited on
; [3.14](../docs/COMPLETED.md#314-the-mathematics-that-is-not-here--done),
; which this program is what finally moved: an entry that had been waiting since
; it was written for a program that wanted an angle.
;
; Each of the six is now one line. That is the shape of the thing that entry was
; arguing about: the cost was never the code, it was that a hand-written one is
; wrong in a range nobody tests and says nothing about it.
;
; `ATN` is BASIC's name for `atan`, and it takes one argument -- so `atan2`,
; which the language gained at the same time, is not needed to finish this and
; sits unused here.

functions := dictionary:new.

functions:atPut("ABS", { m, args | m:onlyArgument("ABS", args):abs }).

; `INT` is a floor and not a truncation, so `INT(-2.5)` is -3. It answers a
; number rather than an integer, because BASIC has one numeric type and the
; distinction Solum makes here is not one a listing can see.
functions:atPut("INT", { m, args | m:onlyArgument("INT", args):floor:asFloat }).

functions:atPut("SGN", { m, args | | v |
    v := m:onlyArgument("SGN", args).
    v:lessThan(0.0):ifElse({ 0.0:sub(1.0) },
        { v:greaterThan(0.0):ifElse({ 1.0 }, { 0.0 }) }) }).

; The standard makes `SQR` of a negative an error rather than a not-a-number,
; and this follows it: Solum would answer `nan` and let it travel.
functions:atPut("SQR", { m, args | | v |
    v := m:onlyArgument("SQR", args).
    v:lessThan(0.0):ifTrue({ m:fail("SQR of {}, which is negative":fill([v])) }).
    v:sqrt }).

; Written with no brackets, which is the standard and is why `nameOrCall` has a
; branch for it. Without `RANDOMIZE` the sequence is the same on every run --
; also the standard, and the thing everybody forgets.
functions:atPut("RND", { m, args |
    args:size:equals(#0):ifFalse({
        m:fail("RND takes no argument in this dialect") }).
    m:rng:fraction }).

; The six that 3.14 was holding, each of them a line once the decision was
; taken. `ATN` is the standard's spelling of `atan`; the rest keep their names.
functions:atPut("SIN", { m, args | m:onlyArgument("SIN", args):sin }).
functions:atPut("COS", { m, args | m:onlyArgument("COS", args):cos }).
functions:atPut("TAN", { m, args | m:onlyArgument("TAN", args):tan }).
functions:atPut("ATN", { m, args | m:onlyArgument("ATN", args):atan }).
functions:atPut("EXP", { m, args | m:onlyArgument("EXP", args):exp }).

; The standard makes `LOG` of a non-positive number an error, where Solum
; answers `-infinity` or `nan` and lets it travel. The stricter rule belongs to
; the language being interpreted, which is the same division `SQR` follows above.
functions:atPut("LOG", { m, args | | v |
    v := m:onlyArgument("LOG", args).
    v:greaterThan(0.0):ifFalse({
        m:fail("LOG of {}, which is not positive":fill([v])) }).
    v:log }).

basic:onlyArgument := { name, args |
    args:size:equals(#1):ifFalse({
        self:fail("{} takes one number":fill([name])) }).
    self:numeric(self:evaluate(args:at(#1))) }.

basic:apply := { n |
    functions:includes(n:name):ifElse(
        { functions:at(n:name):value(self, n:args) },
        { self:userFunction(n) }) }.

; A `DEF` binds its parameter to the actual variable of that name for the
; duration of the call and puts back what was there -- which is the standard's
; rule and is visible: a body that reads the parameter after assigning to it
; elsewhere sees the argument, and the program sees its own value again after.
basic:userFunction := { n | | def, param, saved, answer |
    self:defined:includes(n:name):ifFalse({
        self:fail("{} was never defined":fill([n:name])) }).
    def := self:defined:at(n:name).
    n:args:size:equals(#1):ifFalse({
        self:fail("{} takes one number":fill([n:name])) }).
    param := def:items:at(#1).
    saved := self:variable(param).
    self:vars:atPut(param, self:numeric(self:evaluate(n:args:at(#1)))).
    answer := self:numeric(self:evaluate(def:expr)).
    self:vars:atPut(param, saved).
    answer }.

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
    ; This one was the finding, and now it is a line
    ;
    ; `^` raised for two days, naming
    ; [3.14](../docs/COMPLETED.md#314-the-mathematics-that-is-not-here--done)
    ; and refusing to be stubbed: repeated multiplication answers integer
    ; exponents only, and `exp(y * log x)` needed two more functions the
    ; language also lacked. Landing the whole set made it `pow`.
    op:equals("^"):ifElse({ l:pow(r) }, {
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

runners:atPut('let, { m, st | m:assign(st:target, m:evaluate(st:expr)) }).

runners:atPut('end, { m, st | m:running := false }).

; Not called `print`, although that is the name of the statement: `print` is a
; message every object in this language already answers, and an interpreter that
; overrides it on itself would make `basic:print` mean one thing to a BASIC
; listing and another to anything that ever tried to look at the machine.
runners:atPut('print, { m, st | m:doPrint(st) }).

; `DEF` and `DATA` were read at load, so meeting one at run time is a step over
; it. They are statements because the standard makes them statements, not
; because anything happens when the counter arrives.
runners:atPut('def, { m, st | nil }).
runners:atPut('data, { m, st | nil }).
runners:atPut('option, { m, st | nil }).

runners:atPut('dim, { m, st |
    st:items:do({ each |
        m:arrays:includes(each:at(#1)):ifTrue({
            m:fail("{} is given bounds twice":fill([each:at(#1)])) }).
        m:makeArray(each:at(#1), each:at(#2)) }) }).

runners:atPut('restore, { m, st | m:dataAt := #1 }).

runners:atPut('read, { m, st |
    st:items:do({ place |
        m:dataAt:greaterThan(m:data:size):ifTrue({
            m:fail("READ has run out of DATA") }).
        m:assign(place, m:data:at(m:dataAt)).
        m:dataAt := m:dataAt:add(#1) }) }).

runners:atPut('randomize, { m, st | m:rng := random:new }).

; ---------------------------------------------------------------------------
; INPUT, and the one thing this language cannot do
;
; BASIC prompts with `?` and waits on the same line. **This one cannot**, and
; the reason is [3.18](../docs/ROADMAP.md#318-a-program-cannot-write-without-ending-the-line):
; `display` is the only way a Solum program has to put text on its own output
; and it ends the line, so the `?` goes on a line of its own and the answer is
; typed under it rather than beside it.
;
; The workaround does not work. `system:writeFile("/dev/stdout", "? ")` opens a
; second stream on the same file, and when the output is anything but a
; terminal the two buffer differently -- so the prompt overtakes everything
; printed before it and the transcript comes out in an order the program never
; wrote. That is worse than the missing newline, being wrong rather than ugly,
; and it is why this waits for the entry rather than reaching for the trick.

runners:atPut('input, { m, st | | line, parts |
    m:flushPending.
    "?":display.
    line := system:readLine.
    line:isNil:ifTrue({ m:fail("INPUT has nothing left to read") }).
    parts := line:split(",").
    parts:size:equals(st:items:size):ifFalse({
        m:fail("INPUT wanted {} value(s) and was given {}"
            :fill([st:items:size, parts:size])) }).
    [#1, st:items:size]:loop({ k |
        m:assign(st:items:at(k),
            m:typed(st:items:at(k), parts:at(k):trim)) }) }).

; What was typed, read as whatever the place it is going into holds. An array
; element is always a number, a `$` name is always text, and anything else has
; to look like a number or say so.
basic:typed := { place, text |
    place:kind:equals('variable):and({ self:isText(place:name) }):ifElse(
        { text },
        { { text:asFloat }:onError({ e |
              self:fail("'{}' is not a number":fill([text])) }) }) }.

runners:atPut('stop, { m, st | m:running := false }).

; ---------------------------------------------------------------------------
; The jumps
;
; Every one of these is an assignment to the program counter and a flag saying
; the counter has already moved. That flag is the whole of what control flow
; costs here: no frame is entered, nothing is unwound, and a `GOTO` out of the
; middle of anything is the same statement as a `GOTO` anywhere else -- which is
; why [3.2](../docs/ROADMAP.md#32-no-non-local-return) never comes up, although
; a language with no non-local return interpreting one with `GOTO` sounds like
; it should be the whole problem.

basic:jumpTo := { where |
    self:pc := where.
    self:jumped := true }.

runners:atPut('goto, { m, st | m:jumpTo(st:resolved:at(#1)) }).

runners:atPut('gosub, { m, st |
    m:calls:add(m:pc).
    m:jumpTo(st:resolved:at(#1)) }).

; The stack holds the place the `GOSUB` was at, so the return goes to the one
; after it. Storing the destination instead would be the same number written
; less obviously.
runners:atPut('return, { m, st | | back |
    m:calls:size:equals(#0):ifTrue({ m:fail("RETURN with no GOSUB to return to") }).
    back := m:calls:at(m:calls:size).
    m:calls:removeLast.
    m:jumpTo(back:add(#1)) }).

runners:atPut('if, { m, st |
    m:compare(st):ifTrue({ m:jumpTo(st:resolved:at(#1)) }) }).

runners:atPut('ongoto, { m, st | | k |
    k := m:numeric(m:evaluate(st:expr)):rounded.
    k:lessThan(#1):or({ k:greaterThan(st:resolved:size) }):ifTrue({
        m:fail("ON needs a number from 1 to {}, and chose {}"
            :fill([st:resolved:size, k])) }).
    m:jumpTo(st:resolved:at(k)) }).

; ---------------------------------------------------------------------------
; The loop stack
;
; `FOR` pushes a frame and `NEXT` pops it, so nesting costs an array entry and
; no frames at all. This is the half of the program that would have met
; [3.5](../docs/ROADMAP.md#35-recursion-is-limited-to-about-254-levels) in an
; interpreter for a language whose loops nest lexically, and here it simply
; does not arise.

runners:atPut('for, { m, st | | frame |
    frame := loopFrame:new.
    frame:name := st:name.
    m:vars:atPut(st:name, m:numeric(m:evaluate(st:expr))).
    frame:limit := m:numeric(m:evaluate(st:limit)).
    frame:step := st:step:isNil:ifElse({ 1.0 }, { m:numeric(m:evaluate(st:step)) }).
    frame:body := m:pc:add(#1).

    ; Reaching a `FOR` whose variable is already looping abandons the old loop
    ; rather than starting a second one on the same name. A listing that jumps
    ; back to its own `FOR` is doing something the standard forbids; growing the
    ; stack for ever would make that a slow leak instead of a fresh start.
    m:dropLoop(st:name).
    m:loops:add(frame).

    ; Tested before the body, so an empty range runs it no times -- and the
    ; place to skip to is known because `pairLoops` found it at load.
    m:continues(frame):ifFalse({
        m:loops:removeLast.
        m:jumpTo(st:pair:add(#1)) }) }).

runners:atPut('next, { m, st | | frame |
    m:loops:size:equals(#0):ifTrue({ m:fail("NEXT with no FOR running") }).
    frame := m:loops:at(m:loops:size).
    frame:name:equals(st:name):ifFalse({
        m:fail("NEXT {} but the loop running is FOR {}"
            :fill([st:name, frame:name])) }).
    m:vars:atPut(frame:name, m:variable(frame:name):add(frame:step)).
    m:continues(frame):ifElse(
        { m:jumpTo(frame:body) },
        { m:loops:removeLast }) }).

; A negative step counts down and finishes when it passes the limit, which is
; the only thing the direction changes. A step of zero is legal and loops for
; ever -- the standard says so, and refusing it here would be inventing a rule.
basic:continues := { frame | | v |
    v := self:variable(frame:name).
    frame:step:lessThan(0.0):ifElse(
        { v:greaterOrEqual(frame:limit) },
        { v:lessOrEqual(frame:limit) }) }.

basic:dropLoop := { name | | at |
    at := #0.
    [#1, self:loops:size]:loop({ i |
        self:loops:at(i):name:equals(name):ifTrue({ at := i }) }).
    at:greaterThan(#0):ifTrue({
        { self:loops:size:greaterOrEqual(at) }:whileTrue({
            self:loops:removeLast }) }) }.

; ---------------------------------------------------------------------------
; Comparing
;
; Six relations on numbers and two on strings, which is the standard: `<` on
; text has no meaning in Minimal BASIC, and this refuses it rather than falling
; back on the byte order Solum would happily supply.
;
; **This was written with `ifElseIf` first, and measured, and changed back.**
; It is the one dispatch in this program that is genuinely hot -- every `IF` in
; a running listing comes through here -- and a loop of 20,000 iterations
; driven by `IF` and `GOTO` ran in 0.246s as the staircase below and **0.30s**
; through `ifElseIf`. Twenty-two per cent of the whole interpreter, for six arms
; that a staircase holds legibly anyway.
;
; So the niche `ifElseIf` has turns out to be narrow, and this program found
; both of its edges in a day: it is out of the recursive dispatches on depth,
; and out of the hot one on speed. What is left for it is the flat, cool,
; many-armed case -- the tokeniser, and `disasm.sol`'s constant tags. That is a
; real niche and a small one, and it is the sharpest thing anybody knows about
; whether the VM should take it over. See
; [lib/control.sol](../lib/control.sol), which now records the number.

basic:compare := { st | | l, r, op |
    l := self:evaluate(st:left).
    r := self:evaluate(st:right).
    op := st:op.
    l:isKindOf(float):ifElse({
        r:isKindOf(float):ifFalse({
            self:fail("cannot compare a number with a string") }).
        op:equals("="):ifElse({ l:equals(r) }, {
        op:equals("<>"):ifElse({ l:equals(r):not }, {
        op:equals("<"):ifElse({ l:lessThan(r) }, {
        op:equals("<="):ifElse({ l:lessOrEqual(r) }, {
        op:equals(">"):ifElse({ l:greaterThan(r) }, {
                               l:greaterOrEqual(r) }) }) }) }) }) },
        { r:isKindOf(float):ifTrue({
              self:fail("cannot compare a string with a number") }).
          [ { op:equals("=") },  { l:equals(r) },
            { op:equals("<>") }, { l:equals(r):not },
                                 { self:fail(
                                     "'{}' compares numbers, not strings"
                                         :fill([op])) } ]:ifElseIf }) }.

; ---------------------------------------------------------------------------
; Running

basic:run := { source |
    self:load(source).
    self:running := true.
    self:calls := array:new.
    self:loops := array:new.
    self:arrays := dictionary:new.

    ; Seeded the same way every time, so a listing without `RANDOMIZE` gives
    ; the same answers on every run. That is the standard, and it is what makes
    ; `RANDOMIZE` a statement worth having rather than a formality.
    self:rng := random:new(#19780101).
    self:pc := #1.
    { self:running:and({ self:pc:lessOrEqual(self:order:size) }) }:whileTrue({
        self:atLine := self:order:at(self:pc).
        self:jumped := false.
        self:execute(self:lines:at(self:atLine)).
        self:jumped:ifFalse({ self:pc := self:pc:add(#1) }) }).
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
; A listing from a file
;
;     ./bin/solvm programs/basic.sob programs/basic/sieve.bas
;
; Given a file, that is the whole program: the demonstrations below are skipped,
; because a tool asked to run somebody's listing should not first print its own.
; This is the part of stage five that the rest of stage four needed -- `INPUT`
; reads standard input, so a listing that uses it cannot also be one of the
; demonstrations that run on every build.

system:arguments:size:greaterThan(#0):ifTrue({ | path |
    path := system:arguments:at(#1).
    system:fileExists(path):ifFalse({
        "basic: there is no file {}":fill([path]):display.
        system:exit(#1) }).
    listing:value(system:readFile(path):split("\n")).
    system:exit(#0) }).


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
; It jumps
;
; `IF` takes a line number rather than a statement, so a conditional and the
; work it guards are two lines and a jump. This is the whole of Minimal BASIC's
; control flow and it is enough for anything.

listing:value([
    "10 LET N = 1",
    "20 IF N > 5 THEN 60",
    "30 PRINT N;",
    "40 LET N = N + 1",
    "50 GOTO 20",
    "60 PRINT",
    "70 END"]).
;    1  2  3  4  5

; `GO TO` written as two words is the same statement, which is what the standard
; actually prints -- spaces are not significant, so the tokeniser puts them back
; together before the keyword is looked up.

listing:value([
    "10 GO TO 30",
    "20 PRINT \"skipped\"",
    "30 PRINT \"jumped\"",
    "40 STOP",
    "50 PRINT \"never\""]).
;   jumped

; ---------------------------------------------------------------------------
; It loops
;
; The limit and the step are read once, when the loop starts. A negative step
; counts down. A range that is already empty runs the body no times, and knows
; where to skip to because `FOR` and `NEXT` found each other at load.

listing:value([
    "10 FOR I = 1 TO 5",
    "20 PRINT I;",
    "30 NEXT I",
    "40 PRINT",
    "50 FOR I = 10 TO 1 STEP -3",
    "60 PRINT I;",
    "70 NEXT I",
    "80 PRINT",
    "90 FOR I = 5 TO 1",
    "100 PRINT \"never\"",
    "110 NEXT I",
    "120 END"]).
;    1  2  3  4  5
;    10  7  4  1

; Nesting costs an entry on an array and no frames at all, which is the point
; made at the top of this file arriving in practice.

listing:value([
    "10 FOR I = 1 TO 3",
    "20 FOR J = 1 TO 3",
    "30 PRINT I * J;",
    "40 NEXT J",
    "50 PRINT",
    "60 NEXT I",
    "70 END"]).
;    1  2  3
;    2  4  6
;    3  6  9

; ---------------------------------------------------------------------------
; It calls, and it computes where to go

listing:value([
    "10 FOR I = 1 TO 3",
    "20 GOSUB 100",
    "30 NEXT I",
    "40 END",
    "100 PRINT \"line\"; I",
    "110 RETURN"]).
;   line 1
;   line 2
;   line 3

; `ON` picks by position, counting from one, and being out of range is an error
; rather than a fall-through -- a computed jump that quietly does nothing is a
; bug that looks like a working program.

listing:value([
    "10 FOR I = 1 TO 3",
    "20 ON I GOTO 100, 200, 300",
    "30 NEXT I",
    "40 END",
    "100 PRINT \"one\"",
    "110 GOTO 30",
    "200 PRINT \"two\"",
    "210 GOTO 30",
    "300 PRINT \"three\"",
    "310 GOTO 30"]).
;   one
;   two
;   three

; The `END` on line 40 is not decoration. Without it the loop finishes and
; execution carries straight on into line 100, which is a subroutine and not a
; continuation -- so the program prints `one` a fourth time and then meets a
; `NEXT` with no loop running. That is exactly what BASIC does, and it is the
; oldest trap in the language: the lines after a loop are whatever was typed
; next, not whatever comes logically after.

; ---------------------------------------------------------------------------
; And now it is a language you can write a program in
;
; Nothing below is a feature being shown off. These are the programs a BASIC
; book opens with, and the only reason they are here is that they run.

listing:value([
    "10 REM the first twelve Fibonacci numbers",
    "20 LET A = 0",
    "30 LET B = 1",
    "40 FOR I = 1 TO 12",
    "50 PRINT B;",
    "60 LET C = A + B",
    "70 LET A = B",
    "80 LET B = C",
    "90 NEXT I",
    "100 PRINT",
    "110 END"]).
;    1  1  2  3  5  8  13  21  34  55  89  144

listing:value([
    "10 REM a times table, which is what print zones are for",
    "20 FOR I = 1 TO 4",
    "30 FOR J = 1 TO 4",
    "40 PRINT I * J,",
    "50 NEXT J",
    "60 PRINT",
    "70 NEXT I",
    "80 END"]).
;    1              2              3              4
;    2              4              6              8
;    3              6              9              12
;    4              8              12             16

; **How fast that is**: 420,000 BASIC statements a second for the FOR loop
; above, 384,000 for the same count written with `IF` and `GOTO`, measured on
; 20,000 iterations. The number is here because it is the first thing anybody
; asks of an interpreter written in an interpreted language, and because it was
; the argument for parsing once at load rather than once per pass.

listing:value([
    "10 LET S = 0",
    "20 FOR I = 1 TO 100",
    "30 LET S = S + I",
    "40 NEXT I",
    "50 PRINT \"SUM 1..100 IS\"; S",
    "60 END"]).
;   SUM 1..100 IS 5050

; ---------------------------------------------------------------------------
; It says where a listing is wrong
;
; Each of these is reported and the interpreter carries on, the way
; [evaluator.sol](evaluator.sol) does: a bad listing is input, not a fault.

listing:value(["10 PRINT (1 + 2", "20 END"]).
;   line 10: a ( was never closed
listing:value(["10 LET 3 = 4", "20 END"]).
;   line 10: LET assigns to a variable or an array element
listing:value(["10 LET TOTAL = 1", "20 END"]).
;   line 10: 'TOTAL' is not a variable: a letter, a letter and a digit, or a letter and $
listing:value(["PRINT 1"]).
;   line 0: a line must start with a line number: PRINT 1
listing:value(["10 PRINT 1", "10 PRINT 2"]).
;   line 10: line 10 appears twice
listing:value(["10 WHILE X < 3", "20 END"]).
;   line 10: 'WHILE' is not a statement in Minimal BASIC

; The control flow has its own listing errors, and all of them are found at
; load -- before the program has printed anything, which is the whole reason the
; line numbers are followed in a pass of their own.

listing:value(["10 GOTO 999", "20 END"]).
;   line 10: there is no line 999
listing:value(["10 FOR I = 1 TO 3", "20 END"]).
;   line 10: FOR without a NEXT
listing:value(["10 NEXT I", "20 END"]).
;   line 10: NEXT without a FOR
listing:value(["10 FOR I = 1 TO 3", "20 NEXT J", "30 END"]).
;   line 20: NEXT J closes FOR I
listing:value(["10 RETURN", "20 END"]).
;   line 10: RETURN with no GOSUB to return to
listing:value(["10 IF 1 > 0 THEN PRINT", "20 END"]).
;   line 10: THEN takes a line number in this dialect, not a statement: put the PRINT on its own line and jump to it
listing:value(["10 IF \"A\" < \"B\" THEN 20", "20 END"]).
;   line 10: '<' compares numbers, not strings
listing:value(["10 PRINT \"A\" + 1", "20 END"]).
;   line 10: expected a number, got the string "A"

; ---------------------------------------------------------------------------
; Text, which is the second and last type
;
; A name ending in `$` holds text and a name without one holds a number, and
; that is the whole of the type system. There is no way to declare either and no
; way to convert between them, so a `$` in the wrong place is caught where it
; is written rather than where it is used.

listing:value([
    "10 LET A$ = \"HELLO\"",
    "20 LET B$ = A$",
    "30 PRINT B$; \" AGAIN\"",
    "40 END"]).
;   HELLO AGAIN

; ---------------------------------------------------------------------------
; Arrays, which start at nought
;
; `DIM A(5)` makes **six** cells, 0 to 5, and an array used without any `DIM`
; gets a bound of ten on each subscript. Both are the standard, and between them
; they are why so much old BASIC has exactly eleven of things in it.

listing:value([
    "10 DIM S(5)",
    "20 FOR I = 0 TO 5",
    "30 LET S(I) = I * I",
    "40 NEXT I",
    "50 FOR I = 0 TO 5",
    "60 PRINT S(I);",
    "70 NEXT I",
    "80 PRINT",
    "90 LET U(7) = 3",
    "100 PRINT U(7); U(10)",
    "110 END"]).
;    0  1  4  9  16  25
;    3  0

; Two subscripts, which is as many as this dialect has.

listing:value([
    "10 DIM M(2,3)",
    "20 LET M(2,3) = 99",
    "30 PRINT M(2,3); M(0,0)",
    "40 END"]).
;    99  0

; ---------------------------------------------------------------------------
; The supplied functions, and the six that are not here
;
; `A(1)` and `ABS(1)` are the same shape, so the name is the only thing that
; says which is an array and which is a function -- which is why stage four
; could not be done without most of stage three.

listing:value([
    "10 PRINT ABS(-3); INT(-2.5); SGN(-7); SQR(16)",
    "20 DEF FNS(X) = X * X + 1",
    "30 PRINT FNS(4)",
    "40 END"]).
;    3 -3 -1  4
;    17

; `INT` is a floor and not a truncation, which is why `INT(-2.5)` is -3 above.
; `DEF` is not a statement that runs: it is in force for the whole listing
; wherever it is written, so it is collected at load with the DATA.

; ---------------------------------------------------------------------------
; A listing carrying its own input
;
; Every `DATA` in the program is one list in line order, however the lines are
; scattered. An unquoted word in a `DATA` is text and not a variable, which is
; the standard and catches everybody once.

listing:value([
    "10 DATA 1, 2, THREE",
    "20 READ A, B, C$",
    "30 PRINT A; B; C$",
    "40 RESTORE",
    "50 READ D",
    "60 PRINT D",
    "70 END"]).
;    1  2 THREE
;    1

; ---------------------------------------------------------------------------
; RND, which repeats until you say otherwise
;
; A listing with no `RANDOMIZE` gives the same numbers on every run -- the
; standard's rule, and the reason `RANDOMIZE` is a statement worth having rather
; than a formality. Both of these print the same three numbers, which is the
; claim being made.

listing:value([
    "10 FOR I = 1 TO 3",
    "20 PRINT INT(RND * 100);",
    "30 NEXT I",
    "40 PRINT",
    "50 END"]).
;    18  31  12
listing:value([
    "10 FOR I = 1 TO 3",
    "20 PRINT INT(RND * 100);",
    "30 NEXT I",
    "40 PRINT",
    "50 END"]).
;    18  31  12

; `INPUT` is not demonstrated here, and cannot be: it reads standard input, so a
; listing using it would consume whatever the build happened to be given and
; wait for a terminal that is not there. It is in
; [basic/adder.bas](basic/adder.bas) instead, run by hand:
;
;     $ ./bin/solvm programs/basic.sob programs/basic/adder.bas
;     TWO NUMBERS, SEPARATED BY A COMMA
;     ?
;     3, 4
;     SUM IS 7
;
; The `?` is on a line of its own and should be beside the answer. That is
; [3.18](../docs/ROADMAP.md#318-a-program-cannot-write-without-ending-the-line),
; which this statement found: `display` is the only way this language has to
; write to its own output, and it ends the line.

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
; The half that was missing for two days
;
; `^` and six of the eleven supplied functions raised for two days, naming
; [3.14](../docs/COMPLETED.md#314-the-mathematics-that-is-not-here--done) and
; refusing to be stubbed with anything plausible. That entry had been waiting
; since it was written for a program that wanted an angle. This was the program,
; the decision was taken, and each of the seven became a line.

listing:value([
    "10 PRINT 2 ^ 3; 2 ^ 0.5",
    "20 PRINT SIN(0); COS(0); TAN(0)",
    "30 PRINT EXP(1); LOG(1)",
    "40 END"]).
;    8  1.4142135623730951
;    0  1  0
;    2.718281828459045  0

; `ATN` is the standard's `atan`, and four of it is pi -- which BASIC has no
; constant for, so this is how a listing gets one.

listing:value([
    "10 PRINT ATN(1) * 4",
    "20 END"]).
;    3.141592653589793

; And the left-grouping promised at the top of this file, now that it can be
; shown: `2^3^2` is 64 here and 512 in almost every BASIC since 1978.

listing:value([
    "10 PRINT 2 ^ 3 ^ 2",
    "20 END"]).
;    64

; `LOG` of a non-positive number is an error in the standard, where Solum
; answers `-infinity` and lets it travel. The stricter rule belongs to the
; language being interpreted, which is where `SQR` puts it too.

listing:value(["10 PRINT LOG(0)", "20 END"]).
;   line 10: LOG of 0, which is not positive
