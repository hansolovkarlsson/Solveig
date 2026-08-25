; html.sol -- reading HTML into a tree of elements.
;
;     @include "html.sol".
;
;     page := html:read("<ul><li>one<li>two</ul>").
;     page:find("li"):text:display.            ; one
;     page:findAll("li"):size:print.           ; #2
;
; Found on the search path, so no program has to say where this lives. See
; docs/REFERENCE.md#the-library.
;
; **This parser does not fail.** Every other parser here reports the first
; problem and stops -- solas does, evaluator.sol does, json.sol does -- because
; their input is written by somebody who can fix it. HTML is not like that: it
; is generated, it is served, and it is wrong. A reader that stops is no use, so
; this one recovers and keeps a list of what it recovered from:
;
;     page := html:read("<b>bold</i>").
;     html:complaints:do({ c | c:display }).
;     ; </i> at character 10 closes nothing that is open
;     ; <b> opened at character 1 is never closed
;
; The tree is built against a **stack of open elements** rather than by
; recursion, which is how HTML has to be parsed anyway -- the nesting is in the
; input rather than in the grammar. It has a consequence worth knowing: the
; depth limit that stops json.sol at 124 levels does not apply here at all. See
; ROADMAP 3.5.

@include "text.sol".

html := object:new.

; ---------------------------------------------------------------------------
; What a node is
;
; An element has a name, its attributes, and its children. A child is either
; another element or a plain string -- text is not wrapped, because a string is
; already a value and wrapping it would buy nothing but a message to unwrap it.

html:element := object:new.
html:element:name := "".
html:element:attributes := nil.
html:element:children := nil.
html:element:parent := nil.
html:element:at := #0.

html:newElement := { name, at | | e |
    e := html:element:new.
    e:name := name.
    e:attributes := dictionary:new.
    e:children := array:new.
    e:at := at.
    e }.

; A child points back at its parent, so the tree has cycles in it. That is fine
; here and would not be everywhere: the collector traces from the roots and
; marks what it reaches, so a cycle is collected like anything else. A reference
; count could not do this without a second mechanism.
html:element:add := { child |
    child:isKindOf(string):ifFalse({ child:parent := self }).
    self:children:add(child).
    child }.

; All the text under an element, in order, with the tags taken out.
;
; Walked with a stack rather than by recursion, and the reason is measured
; rather than stylistic: the recursive version of this managed 28 levels of
; nesting before `call depth exceeded`, on a tree the reader had just built
; 50,000 levels deep without complaint. Children are pushed in reverse so they
; come back off in document order.
html:element:text := { | parts, work, node, i |
    parts := array:new.
    work := array:new.
    work:add(self).
    { work:size:greaterThan(#0) }:whileTrue({
        node := work:removeLast.
        node:isKindOf(string):ifElse(
            { parts:add(node) },
            { i := node:children:size.
              { i:greaterOrEqual(#1) }:whileTrue({
                  work:add(node:children:at(i)).
                  i := i:sub(#1) }) }) }).
    parts:join("") }.

html:element:attribute := { name | self:attributes:at(name:asLowercase, nil) }.

; Depth-first, first match wins. `find` answers nil when there is none, which is
; the answer a caller can test rather than an error it has to catch.
;
; The loop stops as soon as there is a match, which is the shape a `break` would
; have written more plainly -- a loop here is left by its condition or by
; failing (ROADMAP 3.13), so the test is in the loop's own condition instead.
; Cheaper here than in json.sol: `found` is the answer this method returns
; anyway, so the condition costs one send rather than a variable of its own.
html:element:find := { name | | found, work, node, i |
    found := nil.
    work := array:new.
    work:add(self).
    { found:isNil:and({ work:size:greaterThan(#0) }) }:whileTrue({
        node := work:removeLast.
        node:isKindOf(string):ifFalse({
            node:equals(self):not:and({ node:name:equals(name) }):ifElse(
                { found := node },
                { i := node:children:size.
                  { i:greaterOrEqual(#1) }:whileTrue({
                      work:add(node:children:at(i)).
                      i := i:sub(#1) }) }) }) }).
    found }.

; Every descendant the block accepts, in document order. `findAll` is this with
; the test being a name, and a caller wanting "every heading" or "every element
; with an id" needs the general form rather than six calls and a sort.
html:element:selectNodes := { test | | out, work, node, i |
    out := array:new.
    work := array:new.
    work:add(self).
    { work:size:greaterThan(#0) }:whileTrue({
        node := work:removeLast.
        node:isKindOf(string):ifFalse({
            node:equals(self):not:and({ test:value(node) })
                :ifTrue({ out:add(node) }).
            i := node:children:size.
            { i:greaterOrEqual(#1) }:whileTrue({
                work:add(node:children:at(i)).
                i := i:sub(#1) }) }) }).
    out }.

; Every match, in document order, and it descends into a match too -- nested
; elements of the same name are all wanted, which `<div><div></div></div>` is
; the ordinary case of.
html:element:findAll := { name |
    self:selectNodes({ node | node:name:equals(name) }) }.

; ---------------------------------------------------------------------------
; The element rules
;
; Three tables, and they are the whole of what this knows about HTML as opposed
; to about angle brackets.

; Void elements have no content and no end tag. An end tag for one is a mistake
; rather than a close.
html:void := dictionary:new.
"area base br col embed hr img input link meta param source track wbr"
    :split(" "):do({ name | html:void:atPut(name, true) }).

; Raw text elements hold text that is not markup: a `<` inside a script is a
; less-than sign, and only the matching end tag ends it.
html:raw := dictionary:new.
"script style":split(" "):do({ name | html:raw:atPut(name, true) }).

; Opening one of these implies the end of the ones listed. This is why
; `<li>one<li>two` is two siblings rather than one nested in the other, and it
; is the part of HTML that surprises people who expect a bracket language.
html:implied := dictionary:new.
html:implied:atPut("li", ["li"]).
html:implied:atPut("dt", ["dt", "dd"]).
html:implied:atPut("dd", ["dt", "dd"]).
html:implied:atPut("tr", ["tr", "td", "th"]).
html:implied:atPut("td", ["td", "th"]).
html:implied:atPut("th", ["td", "th"]).
html:implied:atPut("option", ["option"]).

; And every block-level element closes an open paragraph, which is the rule
; behind `<p>one<p>two` and behind `<p>text<div>` -- a paragraph cannot contain
; either one.
"address article aside blockquote details div dl fieldset figure footer form
 h1 h2 h3 h4 h5 h6 header hr main nav ol p pre section table ul"
    :split(" "):do({ name |
        name := name:split("\n"):join("").
        name:equals(""):ifFalse({
            html:implied:includes(name):ifFalse({
                html:implied:atPut(name, ["p"]) }) }) }).

; ---------------------------------------------------------------------------
; Reading
;
; State on the object, like json.sol: one parse at a time, which is what a
; program does.

; The position lives in a cursor from `scan.sol` rather than in slots here.
; That library exists because this file was one of five that had each written
; the same object -- see COMPLETED.md 5.5.
@include "scan.sol".
html:cur := nil.
html:stack := nil.
html:complaints := nil.

html:complain := { message |
    html:complaints:add("{} at character {}":fill([message, self:cur:pos])) }.

html:space := " \t\n\r".
html:isSpace := { c | c:notNil:and({ self:space:indexOf(c):notNil }) }.
html:skipSpace := {
    self:cur:skipWhile({ c | self:space:indexOf(c):notNil }) }.

; A name is what runs until something that cannot be in one. Deliberately loose:
; the job is to get through a real document, not to police it.
html:nameStop := " \t\n\r/>=".
html:readName := {
    self:cur:takeWhile({ c | self:nameStop:indexOf(c):isNil }):asLowercase }.

; Whether the text at the cursor is `what`, without moving. `scan:looksLike`
; compares exactly and this has to fold case, so it takes and puts the cursor
; back -- which is the same backtracking `readEntity` does below, and the reason
; a cursor's `pos` is assignable and not only readable.
html:looksLike := { what | | start, text |
    start := self:cur:pos.
    text := self:cur:take(what:size).
    self:cur:pos := start.
    text:asLowercase:equals(what) }.

; --- entities --------------------------------------------------------------
;
; The five that matter, plus the numeric forms. A `&` that starts nothing is a
; `&`, which is what every browser does and what a document full of query
; strings needs.

html:entities := dictionary:new.
html:entities:atPut("amp", "&").
html:entities:atPut("lt", "<").
html:entities:atPut("gt", ">").
html:entities:atPut("quot", "\"").
html:entities:atPut("apos", "'").
html:entities:atPut("nbsp", #160:asUtf8).
html:entities:atPut("copy", #169:asUtf8).
html:entities:atPut("mdash", #8212:asUtf8).

html:hexDigits := "0123456789abcdef".

html:readEntity := { | mark, name, digits, code, hex |
    mark := self:cur:pos.
    self:cur:step.                                  ; the &
    self:cur:peek:equals("#"):ifElse(
        { self:cur:step.
          hex := self:cur:peek:notNil:and({ "xX":indexOf(self:cur:peek):notNil }).
          hex:ifTrue({ self:cur:step }).
          digits := self:readDigits(hex).
          digits:equals(""):or({ self:cur:peek:equals(";"):not }):ifElse(
              { self:cur:pos := mark. self:cur:step. "&" },
              { self:cur:step.
                code := digits:asInteger(hex:ifElse({ #16 }, { #10 })).
                { code:asUtf8 }:onError({ e |
                    self:cur:pos := mark.
                    self:complain("&#{}; is not a character":fill([digits])).
                    self:cur:pos := mark:add(digits:size):add(hex:ifElse({ #4 }, { #3 })).
                    "" }) }) },
        { name := self:readEntityName.
          self:entities:includes(name):and({ self:cur:peek:equals(";") }):ifElse(
              { self:cur:step. self:entities:at(name) },
              { self:cur:pos := mark. self:cur:step. "&" }) }) }.

html:readDigits := { hex | | set |
    set := hex:ifElse({ self:hexDigits }, { "0123456789" }).
    self:cur:takeWhile({ c | set:indexOf(c:asLowercase):notNil }) }.

html:readEntityName := {
    self:cur:takeWhile({ c |
        c:asLowercase:greaterOrEqual("a"):and({ c:asLowercase:lessOrEqual("z") })
    }):asLowercase }.

; Text up to the next tag, with entities resolved. Kept as spans so the common
; case is a copy rather than a character at a time.
html:readText := { | out |
    out := "".
    { self:cur:peek:notNil:and({ self:cur:peek:equals("<"):not }) }:whileTrue({
        out := out:concat(self:cur:takeUntil({ c |
            c:equals("<"):or({ c:equals("&") }) })).
        self:cur:peek:equals("&"):ifTrue({
            out := out:concat(self:readEntity) }) }).
    out }.

; --- attributes ------------------------------------------------------------
;
; Quoted, single-quoted, and bare, because all three are out there. An
; attribute with no value gets the empty string rather than a boolean: `checked`
; and `checked=""` mean the same thing in HTML, and answering one type for both
; saves every caller a test.

html:readAttributeValue := { | quote, out |
    self:skipSpace.
    quote := self:cur:peek.
    quote:equals("\""):or({ quote:equals("'") }):ifElse(
        { self:cur:step.
          out := "".
          { self:cur:peek:notNil:and({ self:cur:peek:equals(quote):not }) }
              :whileTrue({
                  out := out:concat(self:cur:takeUntil({ c |
                      c:equals(quote):or({ c:equals("&") }) })).
                  self:cur:peek:equals("&"):ifTrue({
                      out := out:concat(self:readEntity) }) }).
          self:cur:peek:isNil:ifElse(
              { self:complain("an attribute value is never closed") },
              { self:cur:step }).
          out },
        { self:cur:takeWhile({ c |
              self:isSpace(c):not:and({ c:equals(">"):not }) }) }) }.

html:readAttributes := { element | | name |
    { self:skipSpace.
      self:cur:peek:notNil:and({ self:cur:peek:equals(">"):not })
          :and({ self:cur:peek:equals("/"):not }) }:whileTrue({
        name := self:readName.
        name:equals(""):ifElse(
            { self:cur:step },                      ; nothing readable; do not spin
            { self:skipSpace.
              self:cur:peek:equals("="):ifElse(
                  { self:cur:step.
                    element:attributes:atPut(name, self:readAttributeValue) },
                  { element:attributes:atPut(name, "") }) }) }) }.

; --- the open elements -----------------------------------------------------
;
; A plain array used as a stack. This was eight lines of object with its own
; `top` index until [6.23](../docs/COMPLETED.md#623-an-array-cannot-be-popped-or-asked-what-it-holds--done)
; gave arrays `removeLast` -- the workaround was written here first, twice, and
; is what got the messages built. The same is true of `indexOf`: the element
; sets below were delimited strings searched with `string:indexOf`, and they are
; arrays now.

html:open := nil.
html:push := { e | self:open:add(e). e }.
html:pop := { self:open:removeLast }.
html:depth := { self:open:size }.
html:current := { self:open:at(self:open:size) }.

; Is `name` open anywhere? An end tag for something that is not open closes
; nothing, and saying so is better than closing whatever happens to be current.
html:isOpen := { name |
    self:open:collect({ e | e:name }):indexOf(name):notNil }.

html:closeThrough := { name | | done |
    done := false.
    { done:not }:whileTrue({
        self:current:name:equals(name):ifTrue({ done := true }).
        self:pop }) }.

; `<li>` when a `<li>` is open ends it. Not a complaint: it is what the format
; says, and the parser that treats it as an error is the one that is wrong.
html:applyImplied := { name | | closes |
    closes := self:implied:at(name, nil).
    closes:isNil:ifFalse({
        { self:depth:greaterThan(#1)
            :and({ closes:indexOf(self:current:name):notNil }) }
            :whileTrue({ self:pop }) }) }.

; --- tags ------------------------------------------------------------------

html:readEndTag := { | name |
    self:cur:pos := self:cur:pos:add(#2).       ; "</"
    name := self:readName.
    self:skipToTagEnd.
    self:void:includes(name):ifTrue({
        self:complain("</{}> closes a tag that never opens":fill([name])).
        name := "" }).
    name:equals(""):ifFalse({
        self:isOpen(name):ifElse(
            { self:closeThrough(name) },
            ; The recovery that matters most, and the one a stopping parser
            ; cannot make: a stray end tag is dropped and the document carries
            ; on, because the alternative is losing everything after it.
            { self:complain("</{}> closes nothing that is open":fill([name])) }) }) }.

html:skipToTagEnd := {
    self:cur:skipWhile({ c | c:equals(">"):not }).
    self:cur:peek:notNil:ifTrue({ self:cur:step }) }.

html:readStartTag := { | name, e, selfClosing, at |
    at := self:cur:pos.
    self:cur:step.                                  ; "<"
    name := self:readName.
    e := self:newElement(name, at).
    self:readAttributes(e).

    selfClosing := self:cur:peek:equals("/").
    selfClosing:ifTrue({ self:cur:step }).
    self:cur:peek:isNil:ifElse(
        { self:complain("<{}> is never finished":fill([name])) },
        { self:cur:step }).

    self:applyImplied(name).
    self:current:add(e).

    self:void:includes(name):or({ selfClosing }):ifFalse({
        self:push(e).
        self:raw:includes(name):ifTrue({ self:readRawText(name) }) }) }.

; Inside a script or a style, `<` is a less-than sign until the matching end
; tag. Getting this wrong is how a parser swallows a page: one `if (a < b)` and
; everything after it becomes an element.
html:readRawText := { name | | start, closing, done |
    start := self:cur:pos.
    closing := "</":concat(name).
    done := false.
    { done:not }:whileTrue({
        self:cur:peek:isNil:ifElse(
            { done := true },
            { self:looksLike(closing):ifElse(
                { done := true },
                { self:cur:step }) }) }).
    self:cur:pos:greaterThan(start):ifTrue({
        self:current:add(self:cur:src:copyFrom(start, self:cur:pos:sub(#1))) }).
    self:cur:peek:isNil:ifFalse({
        self:cur:pos := self:cur:pos:add(closing:size).
        self:skipToTagEnd.
        self:pop }) }.

; `<!-- -->`, `<!DOCTYPE>` and `<?...?>` are skipped rather than kept. A comment
; that never ends takes the rest of the document with it, which is what a
; browser does too, so it is worth a complaint.
html:skipBang := {
    self:looksLike("<!--"):ifElse(
        { self:cur:pos := self:cur:pos:add(#4).
          { self:cur:peek:notNil:and({ self:looksLike("-->"):not }) }
              :whileTrue({ self:cur:step }).
          self:cur:peek:isNil:ifElse(
              { self:complain("a comment is never closed") },
              { self:cur:pos := self:cur:pos:add(#3) }) },
        { self:skipToTagEnd }) }.

; --- the loop --------------------------------------------------------------

html:read := { source | | document |
    self:cur := scan:on(source).
    self:complaints := array:new.
    self:open := array:new.

    document := self:newElement("#document", #1).
    self:push(document).

    { self:cur:peek:notNil }:whileTrue({
        self:cur:peek:equals("<"):ifElse(
            { self:cur:peekAt(#1):equals("!"):or({ self:cur:peekAt(#1):equals("?") })
                :ifElse(
                { self:skipBang },
                { self:cur:peekAt(#1):equals("/"):ifElse(
                    { self:readEndTag },
                    ; A `<` that starts no tag is a less-than sign. Without this
                    ; the parser would stall on it, and stalling is worse than
                    ; any wrong answer.
                    { self:isNameStart(self:cur:peekAt(#1)):ifElse(
                        { self:readStartTag },
                        { self:current:add("<"). self:cur:step }) }) }) },
            { | run | run := self:readText.
              run:equals(""):ifFalse({ self:current:add(run) }) }) }).

    ; Whatever is still open at the end is closed, and named. An unclosed tag is
    ; the commonest thing wrong with real HTML and the tree is usable anyway --
    ; which is the whole argument for recovering rather than refusing.
    { self:depth:greaterThan(#1) }:whileTrue({
        self:complaints:add("<{}> opened at character {} is never closed"
            :fill([self:current:name, self:current:at])).
        self:pop }).

    ; The cursor is dropped rather than left in a slot, so a parsed document
    ; does not keep the text it came from alive.
    self:cur := nil.
    document }.

html:isNameStart := { c |
    c:notNil:and({ c:asLowercase:greaterOrEqual("a") })
        :and({ c:asLowercase:lessOrEqual("z") }) }.
