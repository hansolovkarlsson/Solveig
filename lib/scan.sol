; scan.sol -- a cursor over text: a position, and the handful of questions you
; ask at one.
;
;     @include "scan.sol".
;
;     s := scan:on("8080ab").
;     s:takeWhile({ c | c:greaterOrEqual("0"):and({ c:lessOrEqual("9") }) }).
;     ; -> "8080", and the cursor is left on "a"
;
; Found on the search path, so no program has to say where this lives. See
; docs/REFERENCE.md#the-library.
;
; ---------------------------------------------------------------------------
; Why this exists
;
; Five files here had written it already. `lib/json.sol`, `lib/html.sol` and
; `experiment/lexer.sol` each define `pos`, `peek` and a step -- two of them
; calling it `step` and the third `advance` -- and `programs/expect.sol` and
; `programs/serve.sol` do the same scanning inline without naming a cursor at
; all. That is ROADMAP 5.5: not a limitation, since every one of those programs
; works, but the same object written five times, where a fix to one is a fix
; nobody makes to the other four.
;
; It is deliberately not a pattern language. What repeated across those files
; was never a pattern -- it was a position, and the two or three things you do
; with one.
;
; ---------------------------------------------------------------------------
; The shape, which was decided rather than chosen
;
; A cursor is an object and not a block returning a block, because
; [3.1](../docs/ROADMAP.md#31-capturing-blocks-cannot-escape-their-frame) does
; not allow the second: a matcher built the combinator way dies with `block
; outlived the frame it was written in`. A cursor holds a position, a position
; is state, and the spelling the language allows is the one this wanted anyway.
;
; Predicates arrive as blocks and are called while the caller is still running,
; which is the case 3.1 permits.

scan := object:new.
scan:src := "".
scan:pos := #1.

; A cursor of its own, so two scans can be in flight at once -- which is the one
; thing `json.sol` says it cannot do, and the reason `on` answers a new object
; rather than resetting this one.
scan:on := { source | | s |
    s := self:new.
    s:src := source.
    s:pos := #1.
    s }.

; ---------------------------------------------------------------------------
; Looking

scan:atEnd := { self:pos:greaterThan(self:src:size) }.

; nil at the end rather than an error, because running out is how a loop
; finishes and not a fault.
scan:peek := { self:atEnd:ifElse({ nil }, { self:src:at(self:pos) }) }.

; `peekAt(#0)` is `peek`; `peekAt(#1)` is the one after it.
scan:peekAt := { n | | i |
    i := self:pos:add(n).
    i:greaterThan(self:src:size):or({ i:lessThan(#1) })
        :ifElse({ nil }, { self:src:at(i) }) }.

; Whether the text from here starts with `what`, without moving. `copyFrom` is
; strict about its end, so the length is checked before it is asked.
scan:looksLike := { what | | last |
    last := self:pos:add(what:size):sub(#1).
    last:greaterThan(self:src:size)
        :ifElse({ false },
                { self:src:copyFrom(self:pos, last):equals(what) }) }.

; ---------------------------------------------------------------------------
; Moving

; Answers the cursor, so it chains.
scan:step := { self:pos := self:pos:add(#1). self }.

; Answers the character it passed, or nil at the end -- where it also stays put,
; because a cursor that walks off the end keeps walking and the position stops
; meaning anything.
scan:next := { | c |
    c := self:peek.
    c:isNil:ifFalse({ self:pos := self:pos:add(#1) }).
    c }.

; Consume `what` if it is here, and say whether it was. Takes a character or a
; longer string, since `looksLike` does not care which.
scan:match := { what |
    self:looksLike(what):ifElse(
        { self:pos := self:pos:add(what:size). true },
        { false }) }.

; ---------------------------------------------------------------------------
; Runs
;
; **The block is never handed nil.** Every one of the fifteen hand-written
; versions of this loop opens `self:peek:notNil:and({ ... })`, which is the
; cursor's business and not the caller's: a predicate here is a question about a
; character, and running out is not a character.

scan:skipWhile := { block |
    { self:atEnd:not:and({ block:value(self:peek) }) }:whileTrue({
        self:pos := self:pos:add(#1) }).
    self }.

; The text consumed, which is empty when the first character already fails.
scan:takeWhile := { block | | start |
    start := self:pos.
    self:skipWhile(block).
    self:since(start) }.

; The other way round, and it stops at the end of the text as well as at the
; block -- so `takeUntil` on something that never arrives answers the rest
; rather than failing.
scan:takeUntil := { block |
    self:takeWhile({ c | block:value(c):not }) }.

; Everything from here to the end, leaving the cursor there.
scan:rest := { self:takeWhile({ c | true }) }.

; The next `n` characters, or fewer if the text runs out first. Clamped by hand
; rather than with `min`, which is `lib/math.sol` and not the language -- this
; file depends on nothing.
scan:take := { n | | start, limit |
    start := self:pos.
    limit := self:src:size:add(#1).
    self:pos := self:pos:add(n).
    self:pos:greaterThan(limit):ifTrue({ self:pos := limit }).
    self:since(start) }.

; ---------------------------------------------------------------------------
; Spans that one predicate cannot describe
;
; `takeWhile` covers a run of one kind of character, which is most of them. It
; does not cover a grammar in parts -- JSON's number is a sign, then digits,
; then perhaps a fraction and an exponent, and what the caller wants at the end
; is all of it. Both were found by converting `json.sol` rather than by
; imagining what a cursor needs, which is what ROADMAP 5.5 said to do.
;
;     start := s:pos.
;     ... any amount of scanning ...
;     s:since(start).          ; everything crossed on the way
;
; `pos` is the mark. There is no `mark` message because there is nothing for it
; to do that reading `pos` does not.
scan:since := { start |
    self:pos:equals(start)
        :ifElse({ "" }, { self:src:copyFrom(start, self:pos:sub(#1)) }) }.
