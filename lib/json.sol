; json.sol -- reading JSON into Solum values, and writing them back out.
;
;     @include "json.sol".
;
;     v := json:read("{\"a\": [1, 2]}").
;     v:at("a"):at(#2):print.          ; #2
;     v:asJson:display.                ; {"a":[1,2]}
;     json:write(v):display.           ; the same, indented
;
; Found on the search path, so no program has to say where this lives. See
; docs/REFERENCE.md#the-library.
;
; The mapping is the obvious one, with two places where JSON and Solum do not
; line up and a choice had to be made:
;
;     object -> dictionary        string -> string
;     array  -> array             true/false -> boolean
;     null   -> nil               number -> integer, or float if it is written
;                                           with a '.' or an exponent
;
; **JSON has one number type and Solum has two.** Going by the spelling is the
; only rule that round-trips: `1` reads back as `1` rather than `1.0`, and
; nothing that was written as a whole number quietly becomes a float. It does
; mean `1` and `1.0` are different values here, which JSON says they are not.
;
; **null and a missing name are both nil.** `at(name, nil)` cannot tell them
; apart, so ask `includes(name)` when the difference matters. That is not this
; file being lazy: it is [absence](../docs/absence.md) showing through, and JSON
; is one of the few formats that draws the line at all.
;
; This file binds one name, `json`, and adds `asJson` to the built-in classes.
; The reader keeps its position in slots on that object, so one parse is in
; flight at a time -- fine for a program, and worth knowing before you call it
; from inside itself.

json := object:new.
json:src := "".
json:pos := #1.

; ---------------------------------------------------------------------------
; Reading

json:fail := { message |
    error:raise("{} at character {}":fill([message, self:pos])) }.

json:peek := {
    self:pos:lessOrEqual(self:src:size)
        :ifElse({ self:src:at(self:pos) }, { nil }) }.

json:step := { self:pos := self:pos:add(#1) }.

json:space := " \t\n\r".
json:skipSpace := {
    { self:peek:notNil:and({ self:space:indexOf(self:peek):notNil }) }
        :whileTrue({ self:step }) }.

json:expect := { c |
    self:peek:equals(c):ifFalse({ self:fail("wanted '{}'":fill([c])) }).
    self:step }.

; Printable ASCII, code 32 to 126, so that a \u escape has somewhere to look.
; This table is here because a character has no number: there is no `asCode` on
; a string and no `asCharacter` on an integer, so the only way from #65 to "A"
; is to have written the alphabet down first. See ROADMAP 6.12.
json:printable := " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~".

; The three control characters Solum can spell. There is no \b and no \f, so a
; JSON file using them cannot be read into a string at all.
json:controls := dictionary:new.
json:controls:atPut(#9,  "\t").
json:controls:atPut(#10, "\n").
json:controls:atPut(#13, "\r").

json:escapes := dictionary:new.
json:escapes:atPut("\"", "\"").
json:escapes:atPut("\\", "\\").
json:escapes:atPut("/",  "/").
json:escapes:atPut("n",  "\n").
json:escapes:atPut("t",  "\t").
json:escapes:atPut("r",  "\r").

json:unicodeEscape := { | hex, code |
    self:pos:add(#3):greaterThan(self:src:size):ifTrue({
        self:fail("\\u wants four hex digits") }).
    hex := self:src:copyFrom(self:pos, self:pos:add(#3)).
    self:pos := self:pos:add(#4).
    ; asInteger(#16) is strict, so a bad digit raises. Caught and re-raised, so
    ; the complaint names the escape and where it was rather than the four
    ; characters on their own.
    code := { hex:asInteger(#16) }:onError({
        self:fail("'{}' is not four hex digits":fill([hex])) }).
    code:greaterOrEqual(#32):and({ code:lessOrEqual(#126) }):ifElse(
        { self:printable:at(code:sub(#31)) },
        { self:controls:at(code, nil):isNil:ifElse(
            { self:fail("\\u{} is outside what a Solum string can hold"
                :fill([hex])) },
            { self:controls:at(code) }) }) }.

json:escape := { | c |
    c := self:peek.
    c:isNil:ifTrue({ self:fail("the input ends in a backslash") }).
    self:step.
    c:equals("u"):ifElse(
        { self:unicodeEscape },
        { self:escapes:at(c, nil):isNil:ifElse(
            { self:fail("\\{} is not an escape this can read":fill([c])) },
            { self:escapes:at(c) }) }) }.

; Copied a span at a time rather than a character at a time: the common case is
; a string with no escapes in it at all, and that is then one `copyFrom` rather
; than one `concat` per character.
json:parseString := { | out, start, done, c |
    self:expect("\"").
    out := "". start := self:pos. done := false.
    { done:not }:whileTrue({
        c := self:peek.
        c:isNil:ifTrue({ self:fail("the string never ends") }).
        c:equals("\""):ifElse(
            { out := out:concat(self:src:copyFrom(start, self:pos:sub(#1))).
              self:step.
              done := true },
            { c:equals("\\"):ifElse(
                { out := out:concat(self:src:copyFrom(start, self:pos:sub(#1))).
                  self:step.
                  out := out:concat(self:escape).
                  start := self:pos },
                { self:step }) }) }).
    out }.

json:digits := "0123456789".
json:isDigit := { c | c:notNil:and({ self:digits:indexOf(c):notNil }) }.

json:digitRun := {
    self:isDigit(self:peek):ifFalse({ self:fail("wanted a digit") }).
    { self:isDigit(self:peek) }:whileTrue({ self:step }) }.

json:parseNumber := { | start, float, text |
    start := self:pos. float := false.
    self:peek:equals("-"):ifTrue({ self:step }).
    ; A leading zero stands alone in JSON: 01 is not a number, it is a zero with
    ; rubbish after it, and saying so here is what makes the caller's "more text
    ; after the value" true rather than merely tidy.
    self:peek:equals("0"):ifElse({ self:step }, { self:digitRun }).
    self:peek:equals("."):ifTrue({
        float := true. self:step. self:digitRun }).
    self:peek:notNil:and({ "eE":indexOf(self:peek):notNil }):ifTrue({
        float := true. self:step.
        self:peek:notNil:and({ "+-":indexOf(self:peek):notNil })
            :ifTrue({ self:step }).
        self:digitRun }).
    text := self:src:copyFrom(start, self:pos:sub(#1)).
    float:ifElse({ text:asFloat }, { text:asInteger }) }.

json:word := { text, value | | end |
    end := self:pos:add(text:size:sub(#1)).
    end:greaterThan(self:src:size):ifTrue({
        self:fail("wanted '{}'":fill([text])) }).
    self:src:copyFrom(self:pos, end):equals(text):ifFalse({
        self:fail("wanted '{}'":fill([text])) }).
    self:pos := end:add(#1).
    value }.

; There is no early return (ROADMAP 3.2), so a loop that stops on a closing
; bracket carries a flag to stop it. It reads worse than a `break` would and it
; is the only shape available; both collections below have the same skeleton.
json:parseArray := { | out, done |
    self:expect("[").
    out := array:new. done := false.
    self:skipSpace.
    self:peek:equals("]"):ifElse(
        { self:step },
        { { done:not }:whileTrue({
            out:add(self:parseValue).
            self:skipSpace.
            self:peek:equals(","):ifElse(
                { self:step },
                { self:expect("]"). done := true }) }) }).
    out }.

json:parseObject := { | out, done, key |
    self:expect("{").
    out := dictionary:new. done := false.
    self:skipSpace.
    self:peek:equals("}"):ifElse(
        { self:step },
        { { done:not }:whileTrue({
            self:skipSpace.
            key := self:parseString.
            self:skipSpace.
            self:expect(":").
            out:atPut(key, self:parseValue).
            self:skipSpace.
            self:peek:equals(","):ifElse(
                { self:step },
                { self:expect("}"). done := true }) }) }).
    out }.

; A chain of comparisons rather than the dictionary of blocks that
; [dispatch.md](../docs/dispatch.md) recommends, and the reason is depth rather
; than speed. `table:at(c, default):value` puts one more frame between a value
; and the value inside it, and with only 62 frames to spend (ROADMAP 3.5) that
; frame is the scarcest thing this program has. Measured, over `[[[...1...]]]`:
;
;     dictionary of blocks    18 levels of nesting before "call depth exceeded"
;     this chain              28
;
; Ten levels, for one message. The jump table is still the right answer when the
; cases are leaves; here every case recurses, and the same frame is paid again
; at every level of the document.
json:parseValue := { | c |
    self:skipSpace.
    c := self:peek.
    c:isNil:ifTrue({ self:fail("wanted a value, found the end of the input") }).
    c:equals("{"):ifElse({ self:parseObject }, {
    c:equals("["):ifElse({ self:parseArray }, {
    c:equals("\""):ifElse({ self:parseString }, {
    c:equals("t"):ifElse({ self:word("true", true) }, {
    c:equals("f"):ifElse({ self:word("false", false) }, {
    c:equals("n"):ifElse({ self:word("null", nil) }, {
    self:isDigit(c):or({ c:equals("-") }):ifElse({ self:parseNumber }, {
        self:fail("'{}' starts no value":fill([c])) }) }) }) }) }) }) }) }.

json:read := { text | | out |
    self:src := text. self:pos := #1.
    out := self:parseValue.
    self:skipSpace.
    self:peek:notNil:ifTrue({ self:fail("more text after the value") }).
    ; The source is dropped rather than left in a slot, so a parsed document
    ; does not keep the text it came from alive.
    self:src := "".
    out }.

; ---------------------------------------------------------------------------
; Writing
;
; `asJson` is a method on `object`, so nil answers "null" without anything
; naming nil's class -- which nothing can, since `nil` names the value and the
; class has no global. It is the one type the language cannot extend, and the
; single root is what makes that not matter here. See ../docs/one-hierarchy.md.

json:outEscapes := dictionary:new.
json:outEscapes:atPut("\"", "\\\"").
json:outEscapes:atPut("\\", "\\\\").
json:outEscapes:atPut("\n", "\\n").
json:outEscapes:atPut("\t", "\\t").
json:outEscapes:atPut("\r", "\\r").

json:quote := { text | | out, start, i, c |
    out := "". start := #1. i := #1.
    { i:lessOrEqual(text:size) }:whileTrue({
        c := text:at(i).
        self:outEscapes:includes(c):ifElse(
            { out := out:concat(text:copyFrom(start, i:sub(#1)))
                        :concat(self:outEscapes:at(c)).
              start := i:add(#1) },
            ; Bytes compare, so this is "below a space" without a code point.
            ; Naming which byte it is would need one, and JSON's answer for it
            ; -- \u00XX -- needs one too, so the honest thing is to refuse.
            { c:lessThan(" "):ifTrue({
                error:raise("a control byte at {} cannot be written: it needs \\u00XX, and a character has no number here":fill([i])) }) }).
        i := i:add(#1) }).
    "\"":concat(out):concat(text:copyFrom(start, text:size)):concat("\"") }.

json:keyText := { k |
    k:isKindOf(string):ifElse(
        { self:quote(k) },
        { k:isKindOf(symbol):ifElse(
            { self:quote(k:asString) },
            { error:raise("a JSON name must be text, and this one is {}"
                :fill([k:asString])) }) }) }.

object:asJson := {
    self:isNil:ifElse(
        { "null" },
        { error:raise("this cannot be written as JSON") }) }.
string:asJson  := { json:quote(self) }.
symbol:asJson  := { json:quote(self:asString) }.
integer:asJson := { self:asString }.
boolean:asJson := { self:asString }.
; A float that happens to be whole prints as `150`, not `150.0`, so writing it
; plainly would hand back an integer on the next read -- the number rule above
; needs holding up from this side too. The exponent form `1e+20` is already
; valid JSON and is left alone.
float:asJson := { | t |
    t := self:asString.
    t:equals("infinity"):or({ t:equals("-infinity") }):or({ t:equals("nan") })
        :ifTrue({ error:raise("JSON has no {}":fill([t])) }).
    t:indexOf("."):isNil:and({ t:indexOf("e"):isNil })
        :ifTrue({ t := t:concat(".0") }).
    t }.
array:asJson := {
    "[":concat(self:collect({ v | v:asJson }):join(",")):concat("]") }.
; Sorted, so that writing the same document twice gives the same text. A
; dictionary hands back its keys in the table's order, which is arbitrary but
; not random -- and arbitrary is not good enough for a file that gets diffed.
dictionary:asJson := {
    "{":concat(self:keys:sorted:collect({ k |
        json:keyText(k):concat(":"):concat(self:at(k):asJson) }):join(","))
       :concat("}") }.

; Only the two that nest need to know about indenting. Everything else inherits
; the version on `object`, which ignores it -- one definition covering nine
; types, which is what the single root is for.
object:asPrettyJson := { indent | self:asJson }.
array:asPrettyJson := { indent | | inner |
    self:size:equals(#0):ifElse({ "[]" }, {
        inner := indent:concat("  ").
        "[\n":concat(self:collect({ v |
            inner:concat(v:asPrettyJson(inner)) }):join(",\n"))
            :concat("\n"):concat(indent):concat("]") }) }.
dictionary:asPrettyJson := { indent | | inner |
    self:size:equals(#0):ifElse({ "{}" }, {
        inner := indent:concat("  ").
        "{\n":concat(self:keys:sorted:collect({ k |
            inner:concat(json:keyText(k)):concat(": ")
                 :concat(self:at(k):asPrettyJson(inner)) }):join(",\n"))
            :concat("\n"):concat(indent):concat("}") }) }.

json:write := { v | v:asPrettyJson("") }.
