; pattern.sol -- regular expressions and substitution, in the subset an editor
; searches with.
;
;     @include "pattern.sol".
;
;     p := pattern:on("^[a-z]*ing$").
;     p:find("everything"):print.       ; #1
;     p:find("thingy"):print.           ; nil
;
;     pattern:on("an"):replaceAllIn("banana", "[&]").   ; "b[an][an]a"
;
; Found on the search path, so no program has to say where this lives. See
; docs/REFERENCE.md#the-library.
;
; ---------------------------------------------------------------------------
; What the language is
;
; The one Kernighan and Pike call the useful half, and vi searches with:
;
;   c        any character that is not one of the below, matching itself
;   .        any one character
;   *        zero or more of the item before it
;   [abc]    any one of those; [a-z] a range; [^abc] anything but
;   ^        at the start of the pattern: the match begins the text
;   $        at the end of the pattern: the match ends the text
;   \        the next character, literally -- `\.`, `\*`, `\[`, `\\`
;
; `^` and `$` are ordinary characters anywhere else, and `*` at the start of a
; pattern is an ordinary character too, because there is nothing before it to
; repeat. That is what vi does and what every editor since has copied.
;
; **What is not here**: no groups, no alternation, no `+` or `?`, no captures,
; no counted repetition. They are the half that wants a different engine -- a
; backtracker over a *tree* rather than over a list -- and nothing here has
; wanted one. Adding them later is a rewrite of `matchFrom` and nothing else,
; which is the reason to leave the door in that shape.
;
; ---------------------------------------------------------------------------
; Three things the language decided about this file
;
; **The pattern is compiled to an array of items, once.** A matcher that reads
; the pattern text as it goes re-reads `[a-z]` at every position of every line,
; and an editor searching a file asks the same pattern a hundred thousand
; questions. `on` answers an object holding the items; `find` uses it.
;
; **Recursion happens at a `*` and nowhere else**, and what that is worth was
; measured rather than assumed.
; [3.5](../docs/ROADMAP.md#35-recursion-is-limited-to-about-254-levels) is the
; ceiling, and each nested call here is one frame: **250 stars in one pattern
; work and 251 answers `call depth exceeded`**, which is not a pattern anybody
; writes. A run of ordinary items is walked in a *loop*, so a 240-character
; literal pattern is ordinary too.
;
; The shape that would have hurt is the textbook one, where a star recurses over
; the **text** -- `match(star) = match(rest, here) or match(star, here + 1)`.
; The depth is then the length of the line being searched, and a line is longer
; than a pattern by a factor nobody controls: the 2,001-character line this was
; tested on would have needed two thousand frames, and gets two. Both forms are
; a page of code and only one of them runs here, which is the whole of why this
; file is shaped as it is.
;
; **`find(text)` and `findFrom(text, at)` are two names for one idea**, because
; a block has one parameter list and a slot holds one block: a library written
; in Solum cannot answer the same message with two arities the way `at(key)` and
; `at(key, default)` do on a dictionary. Primitives can; this cannot. The names
; are the honest way round it, and are not a workaround for anything else.

@include "scan.sol".

; ---------------------------------------------------------------------------
; The compiled form
;
; One item per element of the pattern: a thing to match, and whether a `*`
; follows it. `end` is the `$`, which matches no character at all -- it is a
; question about where the cursor is rather than about what is under it.

pattern := object:new.
pattern:source := "".
pattern:items := nil.
pattern:anchored := false.          ; the pattern opened with `^`

; Hung off `pattern` rather than bound beside it, so this file claims **one**
; global. [6.21](../docs/COMPLETED.md#621-two-libraries-binding-one-name-collide-silently--done)
; is why that is worth a line: a library that takes two common words takes them
; from every program that includes it.
pattern:item := object:new.
pattern:item:kind := 'literal.      ; 'literal, 'any, 'set or 'end
pattern:item:value := "".           ; the character, for 'literal
pattern:item:members := "".         ; the characters, for 'set, ranges expanded
pattern:item:negated := false.      ; whether the set is the ones it does *not*
pattern:item:star := false.

; ---------------------------------------------------------------------------
; Reading a pattern
;
; The cursor is [scan.sol](scan.sol)'s, which is why this file includes it. A
; program that includes both gets one copy: `@include` compiles a file once,
; however many times it is named.

pattern:on := { source | | p, s, item |
    p := self:new.
    p:source := source.
    p:items := array:new.
    p:anchored := false.

    s := scan:on(source).
    s:looksLike("^"):ifTrue({ p:anchored := true. s:step }).

    { s:atEnd:not }:whileTrue({
        ; `$` is the end only as the last character. `a$b` searches for three
        ; characters, which is the rule vi has and the one that lets a pattern
        ; hold a price without being escaped.
        s:looksLike("$"):and({ s:pos:equals(source:size) }):ifElse(
            { item := self:item:new.
              item:kind := 'end.
              p:items:add(item).
              s:step },
            { item := p:itemFrom(s).
              ; A `*` with something before it repeats it; with nothing before
              ; it, it is a character like any other, and `itemFrom` has
              ; already read it as one.
              s:looksLike("*"):ifTrue({ item:star := true. s:step }).
              p:items:add(item) }) }).
    p }.

pattern:itemFrom := { s | | item, c |
    item := self:item:new.
    c := s:next.

    c:equals("\\"):ifTrue({
        s:atEnd:ifTrue({
            error:raise("a pattern cannot end with a backslash") }).
        item:kind := 'literal.
        item:value := s:next }).

    c:equals("."):ifTrue({ item:kind := 'any }).

    c:equals("["):ifTrue({ self:setInto(item, s) }).

    ["\\", ".", "["]:indexOf(c):isNil:ifTrue({
        item:kind := 'literal.
        item:value := c }).

    item }.

; A class: `[abc]`, `[^abc]`, `[a-z]`, and `-` first or last being itself. The
; members are expanded into a string rather than kept as ranges, because
; `indexOf` is then the whole of the membership test and a range in a search
; pattern is never large.
pattern:setInto := { item, s | | c, from, to, closed |
    item:kind := 'set.
    item:members := "".
    item:negated := false.
    closed := false.

    s:looksLike("^"):ifTrue({ item:negated := true. s:step }).

    { closed:not }:whileTrue({
        s:atEnd:ifTrue({ error:raise("a pattern has an unclosed '['") }).
        c := s:next.
        c:equals("]"):ifElse(
            { closed := true },
            { c:equals("\\"):ifTrue({
                  s:atEnd:ifTrue({
                      error:raise("a pattern cannot end with a backslash") }).
                  c := s:next }).
              ; A range, unless the `-` is the last thing before the `]`.
              s:looksLike("-"):and({ s:peekAt(#1):notNil })
                  :and({ s:peekAt(#1):equals("]"):not }):ifElse(
                  { s:step.
                    from := c:asByte.
                    to := s:next:asByte.
                    to:lessThan(from):ifTrue({
                        error:raise("a pattern has a range that runs backwards") }).
                    [from, to]:loop({ n |
                        item:members := item:members:concat(n:asCharacter) }) },
                  { item:members := item:members:concat(c) }) }) }) }.

; ---------------------------------------------------------------------------
; Matching
;
; `matchFrom` answers where a match beginning at `at` *ends*, or nil. The end
; rather than a boolean, because the one thing a caller always wants next is
; what it matched -- and because nil and an index are already how absence is
; spelled everywhere else here.
;
; The loop walks items that have no choice to make. The recursion is the two
; lines under `star`, and only those: a star tries the longest run first and
; gives a character back at a time until the rest of the pattern fits, which is
; leftmost-longest and is what everybody's `.*` expects.

pattern:accepts := { item, c |
    item:kind:equals('any):ifElse({ true }, {
    item:kind:equals('literal):ifElse({ item:value:equals(c) }, {
    item:kind:equals('set):ifElse(
        { item:members:indexOf(c):notNil:equals(item:negated:not) },
        { false }) }) }) }.

pattern:matchFrom := { text, at, index | | ti, pi, current, done, answer, run |
    ti := at.
    pi := index.
    done := false.
    answer := nil.

    { done:not }:whileTrue({
        pi:greaterThan(self:items:size):ifElse(
            { answer := ti. done := true },
            { current := self:items:at(pi).

              current:star:ifTrue({
                  ; How far it can run, then back off a character at a time.
                  run := ti.
                  { run:lessOrEqual(text:size)
                      :and({ self:accepts(current, text:at(run)) }) }
                      :whileTrue({ run := run:add(#1) }).
                  { answer:isNil:and({ run:greaterOrEqual(ti) }) }:whileTrue({
                      answer := self:matchFrom(text, run, pi:add(#1)).
                      run := run:sub(#1) }).
                  done := true }).

              current:star:ifFalse({
                  current:kind:equals('end):ifElse(
                      { ti:greaterThan(text:size):ifTrue({ answer := ti }).
                        done := true },
                      { ti:greaterThan(text:size):ifElse(
                          { done := true },
                          { self:accepts(current, text:at(ti)):ifElse(
                              { ti := ti:add(#1). pi := pi:add(#1) },
                              { done := true }) }) }) }) }) }).
    answer }.

; ---------------------------------------------------------------------------
; Finding
;
; Where the first match begins, or nil. An anchored pattern can only begin at
; the first character, so it is asked once rather than at every position.

pattern:findFrom := { text, at | | from, found, last |
    from := at:lessThan(#1):ifElse({ #1 }, { at }).
    found := nil.

    self:anchored:and({ from:greaterThan(#1) }):ifFalse({
        ; One past the end is a position too: `x*` matches nothing at the end of
        ; a line, and a search that could not stand there would miss it.
        last := self:anchored:ifElse({ #1 }, { text:size:add(#1) }).
        { found:isNil:and({ from:lessOrEqual(last) }) }:whileTrue({
            self:matchFrom(text, from, #1):notNil:ifTrue({ found := from }).
            from := from:add(#1) }) }).
    found }.

pattern:find := { text | self:findFrom(text, #1) }.

pattern:matches := { text | self:find(text):notNil }.

; The last match beginning *before* `at`, for a search that runs backwards.
; Found by looking forward, because a pattern is read left to right and a
; matcher that ran the other way would be a second engine.
pattern:findLast := { text, at | | from, found, hit |
    from := #1.
    found := nil.
    { from:lessThan(at) }:whileTrue({
        hit := self:findFrom(text, from).
        hit:isNil:or({ hit:greaterOrEqual(at) }):ifElse(
            { from := at },
            { found := hit. from := hit:add(#1) }) }).
    found }.

; Where a match beginning at `at` ends, or nil -- the half `find` does not
; answer, kept separate because most callers never ask it.
pattern:endOfMatchAt := { text, at | self:matchFrom(text, at, #1) }.

; ---------------------------------------------------------------------------
; Replacing
;
; The other half of `s/find/replace/`, and the reason `endOfMatchAt` exists at
; all: putting something in a match's place needs to know where the match ends,
; which is the one question `find` does not answer.
;
; **`&` in the replacement is what was matched**, which is sed's rule and vi's,
; and `\&` is an ampersand. `\` escapes itself and anything else it precedes, so
; `\\` is one backslash. A replacement ending in a backslash is refused the same
; way a pattern ending in one is: it is always a typing mistake and never a
; request.
;
; **A match that consumed nothing gets out of its own way.** `x*` matches the
; empty string everywhere, and a loop that searched again from where it started
; would replace forever -- so a zero-width match carries the character it stood
; on across and moves one further. `s/x*/-/g` over `abc` is `-a-b-c-`, which is
; what sed gives and is the only answer that terminates.

pattern:replacementFor := { replacement, matched | | out, s, c |
    out := "".
    s := scan:on(replacement).
    { s:atEnd:not }:whileTrue({
        c := s:next.
        c:equals("\\"):ifElse(
            { s:atEnd:ifTrue({
                  error:raise("a replacement cannot end with a backslash") }).
              out := out:concat(s:next) },
            { c:equals("&"):ifElse(
                { out := out:concat(matched) },
                { out := out:concat(c) }) }) }).
    out }.

pattern:substituteIn := { text, replacement, all | | out, at, start, stop, done |
    out := "".
    at := #1.
    done := false.

    { done:not }:whileTrue({
        start := self:findFrom(text, at).
        start:isNil:ifElse(
            { done := true },
            { stop := self:endOfMatchAt(text, start).
              out := out:concat(text:copyFrom(at, start:sub(#1)))
                        :concat(self:replacementFor(
                            replacement, text:copyFrom(start, stop:sub(#1)))).
              stop:equals(start):ifTrue({
                  start:lessOrEqual(text:size):ifTrue({
                      out := out:concat(text:at(start)) }).
                  stop := start:add(#1) }).
              at := stop.
              all:ifFalse({ done := true }) }) }).

    ; What is left, if the last match did not run to the end. One past the end
    ; is a position `copyFrom` will take; two past it is not, and a zero-width
    ; match at the very end leaves the cursor there.
    out:concat(at:greaterThan(text:size):ifElse(
        { "" },
        { text:copyFrom(at, text:size) })) }.

pattern:replaceIn := { text, replacement |
    self:substituteIn(text, replacement, false) }.

pattern:replaceAllIn := { text, replacement |
    self:substituteIn(text, replacement, true) }.

; How many non-overlapping matches there are, which is what a substitution has
; to report and cannot get from comparing the text with itself -- replacing `a`
; with `a` changes nothing and is still a substitution.
pattern:countIn := { text | | n, at, start, stop, done |
    n := #0.
    at := #1.
    done := false.
    { done:not }:whileTrue({
        start := self:findFrom(text, at).
        start:isNil:ifElse(
            { done := true },
            { n := n:add(#1).
              stop := self:endOfMatchAt(text, start).
              at := stop:equals(start):ifElse({ start:add(#1) }, { stop }) }) }).
    n }.
