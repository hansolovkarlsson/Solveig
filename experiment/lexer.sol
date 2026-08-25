; lexer.sol -- Solum's tokens, scanned by Solum.
;
;     @include "lexer.sol".
;
;     lexer:on("a := #45.").
;     { lexer:atEnd:not }:whileTrue({ | t |
;         t := lexer:next.
;         "{} {}":fill([t:at("type"), t:at("text")]):display }).
;
; Found on the search path, so no program has to say where this lives. See
; docs/REFERENCE.md#the-library.
;
; **Stage 1 of asking whether Solas could be written in Solum** -- see
; [ideas.md](../docs/ideas.md#solas-written-in-solum--self-hosting).
; [emit.sol](emit.sol) answered the back end; this is the front.
;
; It is written against [solas/src/lexer.c](../solas/src/lexer.c) rule for rule,
; and it is held to it: `make test` scans every `.sol` file in the repository
; with both and compares the tokens, position by position. Not "produces
; something reasonable" -- the same tokens, on the same lines, in the same
; columns.
;
; **The question this file was written to answer** is whether Solum needs a
; pattern class or a built-in scanner before it can tokenise anything serious.
; The answer is in the length of this file and in the notes below: it does not.
; What character scanning wants here is `at`, `copyFrom` and comparison, and the
; language has had all three since before it had a garbage collector.
;
; It binds one global, `lexer`, which is a word a program might want for itself.
; The collision is warned about at compile time -- ROADMAP 6.21 -- and the
; alternative, hanging methods off `string`, would be worse: scanning is *state*
; and a string is a value.

; The position lives in a cursor from `lib/scan.sol`. This file was one of the
; five that had each written that object for themselves -- see COMPLETED.md 5.5
; -- and the header above already argued its shape: scanning is state, and a
; string is a value. What stays here is the line accounting, which is the
; lexer's business and not a cursor's.
@include "scan.sol".

lexer := object:new.

lexer:cur := nil.
lexer:line := #1.
lexer:lineStart := #1.    ; where the line `pos` sits on begins

; Where the token being scanned began, and the line it began *on*. A string
; literal may span lines, so the line it ends on is not the line it is reported
; at -- the same reason the C scanner carries these separately.
lexer:start := #1.
lexer:tokenLine := #1.
lexer:tokenLineStart := #1.

; ---------------------------------------------------------------------------
; Starting
;
; A `#!` on the very first line is skipped so a `.sol` can be marked executable.
; The newline is deliberately left for the scanner to find, so the line after a
; shebang is line 2 and every position names the line an editor shows.

lexer:on := { source |
    self:cur := scan:on(source).
    self:line := #1.
    self:lineStart := #1.
    self:start := #1.
    self:tokenLine := #1.
    self:tokenLineStart := #1.
    source:size:greaterOrEqual(#2):and({ source:copyFrom(#1, #2):equals("#!") })
        :ifTrue({
            self:cur:skipWhile({ c | c:equals("\n"):not }).
            self:lineStart := self:cur:pos }) }.

; ---------------------------------------------------------------------------
; The cursor

lexer:atEnd   := { self:cur:atEnd }.
lexer:peek    := { self:cur:peek }.
lexer:peekNext := { self:cur:peekAt(#1) }.

; Not `scan:next`, which stays put at the end. This one has always stepped past
; it, and the callers below count on the position moving.
lexer:advance := { | c | c := self:cur:peek. self:cur:pos := self:cur:pos:inc. c }.

; Every place that crosses a newline goes through here, so the line number and
; the line's first character cannot come apart -- and a column is only
; meaningful if they agree.
lexer:newline := {
    self:line := self:line:inc.
    self:cur:pos := self:cur:pos:inc.
    self:lineStart := self:cur:pos }.

lexer:match := { c | self:cur:match(c) }.

; ---------------------------------------------------------------------------
; What a character is
;
; Comparison on one-character strings, which orders by bytes. No table and no
; pattern: `"0"` to `"9"` is a range because ASCII says so, and saying it that
; way reads closer to the rule than a set of 10 would.

lexer:isDigit := { c |
    c:notNil:and({ c:greaterOrEqual("0"):and({ c:lessOrEqual("9") }) }) }.

lexer:isAlpha := { c |
    c:notNil:and({
        c:greaterOrEqual("a"):and({ c:lessOrEqual("z") })
            :or({ c:greaterOrEqual("A"):and({ c:lessOrEqual("Z") }) })
            :or({ c:equals("_") }) }) }.

lexer:isNameByte := { c | self:isAlpha(c):or({ self:isDigit(c) }) }.

; ---------------------------------------------------------------------------
; Making one
;
; The text is the raw source between where the token began and where the cursor
; now is -- quotes and backslashes included, undecoded. Which escapes are legal
; is the compiler's business, decided in one place when it decodes them, and the
; C scanner draws the line in exactly the same spot.

lexer:token := { type | | t |
    t := dictionary:new.
    t:atPut("type", type).
    t:atPut("text", self:cur:src:copyFrom(self:start, self:cur:pos:dec)).
    t:atPut("line", self:tokenLine).
    t:atPut("column", self:start:sub(self:tokenLineStart):inc).
    t:atPut("message", nil).
    t }.

; The offending characters stay in the text and the complaint goes beside them,
; so an error token can be pointed at like any other.
lexer:error := { message | | t |
    t := self:token('error).
    t:atPut("message", message).
    t }.

; ---------------------------------------------------------------------------
; Whitespace and comments carry no tokens

lexer:skipIgnorable := { | going |
    going := true.
    { going }:whileTrue({ | c |
        c := self:peek.
        c:isNil:ifTrue({ going := false }).
        going:ifTrue({
            c:equals("\n"):ifElse(
                { self:newline },
                { " \r\t":indexOf(c):notNil:ifElse(
                    { self:cur:pos := self:cur:pos:inc },
                    { c:equals(";"):ifElse(
                        { self:cur:skipWhile({ c | c:equals("\n"):not }) },
                        { going := false }) }) }) }) }) }.

; ---------------------------------------------------------------------------
; The kinds that have to be scanned

lexer:identifier := {
    self:cur:skipWhile({ c | self:isNameByte(c) }).
    self:token('ident) }.

; `#45` -- the `#` is a type tag, so the digits must follow immediately.
lexer:integer := {
    self:match("-").
    self:isDigit(self:peek):ifElse(
        { self:cur:skipWhile({ c | self:isDigit(c) }).
          self:peek:equals("."):and({ self:isDigit(self:peekNext) }):ifElse(
              { self:error("'#' marks an integer; drop it for a float") },
              { self:token('int) }) },
        { self:error("expected digits after '#'") }) }.

; A bare number is a float. The `.` only continues the number when a digit
; follows, so `45.` is the float 45 plus a statement terminator.
lexer:number := { | before |
    self:cur:skipWhile({ c | self:isDigit(c) }).
    self:peek:equals("."):and({ self:isDigit(self:peekNext) }):ifTrue({
        self:cur:pos := self:cur:pos:inc.
        self:cur:skipWhile({ c | self:isDigit(c) }) }).

    ; An exponent, but only if it really is one. A bare `e` is left alone rather
    ; than claimed, so `1e` stays a float followed by an identifier instead of
    ; becoming a malformed number -- which is why the cursor is remembered and
    ; put back.
    self:peek:equals("e"):or({ self:peek:equals("E") }):ifTrue({
        before := self:cur:pos.
        self:cur:pos := self:cur:pos:inc.
        self:peek:equals("+"):or({ self:peek:equals("-") })
            :ifTrue({ self:cur:pos := self:cur:pos:inc }).
        self:isDigit(self:peek):ifElse(
            { self:cur:skipWhile({ c | self:isDigit(c) }) },
            { self:cur:pos := before }) }).
    self:token('float) }.

; Scanning only needs to know that a backslash claims the next character, so
; that `\"` does not end the string.
lexer:string := { | going |
    going := true.
    { going }:whileTrue({
        self:atEnd:or({ self:peek:equals("\"") }):ifElse(
            { going := false },
            { self:peek:equals("\n"):ifElse(
                { self:newline },
                { self:peek:equals("\\"):ifTrue({ self:cur:pos := self:cur:pos:inc }).
                  self:atEnd:ifElse({ going := false },
                                    { self:cur:pos := self:cur:pos:inc }) }) }) }).
    self:atEnd:ifElse(
        { self:error("unterminated string") },
        { self:cur:pos := self:cur:pos:inc.                 ; the closing quote
          self:token('string) }) }.

; `'foo` -- a quote prefix and no closing quote, the way Lisp reads a symbol.
lexer:symbol := {
    self:isAlpha(self:peek):ifElse(
        { self:cur:skipWhile({ c | self:isNameByte(c) }).
          self:token('symbol) },
        { self:error("expected a name after \"'\"") }) }.

; `@include` -- the `@` is part of the token, so a directive is one lexeme and
; never an identifier that happens to follow a symbol.
lexer:directive := {
    self:isAlpha(self:peek):ifElse(
        { self:cur:skipWhile({ c | self:isNameByte(c) }).
          self:token('directive) },
        { self:error("expected a name after '@'") }) }.

; ---------------------------------------------------------------------------
; The one-character tokens
;
; A dictionary rather than a chain of comparisons, and it costs nothing: these
; are symbols being looked up, not blocks being called, so there is no frame per
; character the way there would be with a table of blocks -- the measurement
; ROADMAP 3.5 records for `lib/json.sol`.

lexer:single := dictionary:new.
lexer:single:atPut("(", 'lparen).
lexer:single:atPut(")", 'rparen).
lexer:single:atPut("{", 'lbrace).
lexer:single:atPut("}", 'rbrace).
lexer:single:atPut("[", 'lbracket).
lexer:single:atPut("]", 'rbracket).
lexer:single:atPut("|", 'pipe).
lexer:single:atPut(",", 'comma).
lexer:single:atPut(".", 'dot).

; ---------------------------------------------------------------------------
; The next token

lexer:next := { | c, kind |
    self:skipIgnorable.
    self:start := self:cur:pos.
    self:tokenLine := self:line.
    self:tokenLineStart := self:lineStart.

    self:atEnd:ifElse(
        { self:token('eof) },
        { c := self:advance.
          self:isAlpha(c):ifElse(
            { self:identifier },
            { self:isDigit(c):ifElse(
                { self:number },
                { kind := self:single:at(c, nil).
                  kind:notNil:ifElse(
                    { self:token(kind) },
                    { c:equals("#"):ifElse(
                        { self:integer },
                        { c:equals("\""):ifElse(
                            { self:string },
                            { c:equals("'"):ifElse(
                                { self:symbol },
                                { c:equals("@"):ifElse(
                                    { self:directive },
                                    ; ':' followed by '=' is one token, never a
                                    ; send. This is why selectors must be
                                    ; identifiers: if '=' were one, `a:=(b)`
                                    ; would be ambiguous.
                                    { c:equals(":"):ifElse(
                                        { self:match("="):ifElse(
                                            { self:token('assign) },
                                            { self:token('colon) }) },
                                        { c:equals("-"):and({ self:isDigit(self:peek) })
                                            :ifElse(
                                            { self:number },
                                            { c:equals("-"):ifElse(
                                                { self:error("'-' must be followed by digits") },
                                                { self:error("unexpected character") }) }) })
                                    }) }) }) }) }) }) }) }) }.

; Every token in one array, which is what a parser wants and what the
; comparison test reads. Ends with the `eof` token, so the array is never empty
; and a parser never has to ask whether there is one more.
lexer:all := { source | | out, t, going |
    self:on(source).
    out := array:new.
    going := true.
    { going }:whileTrue({
        t := self:next.
        out:add(t).
        t:at("type"):equals('eof):ifTrue({ going := false }) }).
    out }.
