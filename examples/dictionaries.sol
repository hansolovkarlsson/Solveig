; dictionaries.sol -- values kept under keys, found by hashing.
; Run with:  ./bin/solas examples/dictionaries.sol && ./bin/solvm examples/dictionaries.sob

; There is no literal for a dictionary the way [#1, #2] is one for an array.
; `new` makes an empty one, and it is one of only two classes that construct --
; a dictionary is mutable, so there is a fresh distinct one to hand back.
ages := dictionary:new.
ages:size:print.                 ; #0

; `of` builds one in a single expression, keys and values alternating. That is
; all a literal would be: [#1, #2] is itself a spelling over `array:of` rather
; than a form the compiler knows, so the two are the same distance from the
; machine.
sizes := dictionary:of("small", #1, "large", #9).
sizes:size:print.                ; #2
sizes:at("large"):print.         ; #9
dictionary:of:size:print.        ; #0   -- no arguments, an empty one

; **Which is what lets a dictionary be written where it is used.** A dictionary
; could always be *passed*; what it could not be was built as an argument,
; which took three statements and a name for a value wanted once.
describe := { bag | "{} of them":fill([bag:at("count")]):display }.
describe:value(dictionary:of("count", #7)).      ; 7 of them

; A key must be a value, for the reason `at` gives below, and an odd number of
; arguments is a missing value rather than a shorter dictionary:
{ dictionary:of("small") }:onError({ e | e:message:display }).
                                 ; 'of' takes a key and a value for each entry, and got 1 argument -- the odd one has no value to go with it

; atPut binds and answers the value stored, so it chains like an assignment.
ages:atPut("ada", #36).
ages:atPut("grace", #45).
ages:atPut("alan", #41).
ages:size:print.                 ; #3

; Binding a key again replaces it rather than adding a second one.
ages:atPut("ada", #37).
ages:size:print.                 ; #3
ages:at("ada"):print.            ; #37

; `at` is an error when the key is not there -- the same answer an out-of-range
; index gets, and for the same reason: a program asking for something it has not
; got is wrong about something.
;
;   ages:at("nobody")   ->  no key "nobody" in the dictionary
;
; `at(key, default)` is for a lookup that may legitimately miss, and it is the
; form a counter wants.
ages:at("nobody", #0):print.     ; #0
ages:includes("nobody"):print.   ; false
ages:includes("ada"):print.      ; true

; ---------------------------------------------------------------------------
; Counting, which is what a dictionary is mostly for

text := "the quick brown fox jumps over the lazy dog the fox".
counts := dictionary:new.
text:split(" "):do({ word |
    counts:atPut(word, counts:at(word, #0):add(#1))
}).

counts:at("the"):print.          ; #3
counts:at("fox"):print.          ; #2
counts:at("dog"):print.          ; #1

; ---------------------------------------------------------------------------
; Walking one
;
; `do` runs the block once per value, one argument a call, exactly as an array's
; does. `keysAndValuesDo` is the two-argument form.

total := #0.
counts:do({ n | total := total:add(n) }).
total:print.                     ; #11 -- the words, counted

; keys and values answer arrays. Their order is the table's, which is to say no
; order at all -- so sort before showing anything.
counts:keys:size:print.          ; #8 distinct words
counts:keys:sorted:join(" "):display.

; `values` is the other half, and answers an array like `keys` does. `do` above
; walked the same numbers without building one, which is the difference between
; the two: ask for `values` when you want an array to work on rather than a walk.
counts:values:select({ n | n:greaterThan(#1) }):size:print.   ; #2 words repeat

; A word appearing more than once, found by asking the pairs.
repeated := array:new.
counts:keysAndValuesDo({ word, n |
    n:greaterThan(#1):ifTrue({ repeated:add(word) })
}).
repeated:sorted:print.           ; ["fox", "the"]

; ---------------------------------------------------------------------------
; A dictionary of blocks is a switch statement
;
; A block is a value and a dictionary holds values, so a table of blocks under
; keys dispatches on one. There is no `switch` in this language and no need for
; one -- and this is faster than a chain of comparisons, being one hash whatever
; the number of cases. See docs/dispatch.md.

action := dictionary:new.
action:atPut('red,   { "stop" }).
action:atPut('amber, { "wait" }).
action:atPut('green, { "go" }).

; `at(key, default)` is the whole trick: it makes the default case one message
; rather than a lookup, a test and a branch. That form was added so a counter
; could say `counts:at(word, #0):add(#1)`, and it turns out to be exactly what a
; switch wants.
switch := { light | action:at(light, { "not a light" }):value }.

switch:value('red):display.      ; stop
switch:value('green):display.    ; go
switch:value('purple):display.   ; not a light

; The blocks may take arguments, so a case can use what it matched.
reply := dictionary:new.
reply:atPut(#404, { n | "no page {}":fill([n]) }).
reply:at(#404, { n | "status {}":fill([n]) }):value(#404):display.   ; no page 404
reply:at(#500, { n | "status {}":fill([n]) }):value(#500):display.   ; status 500

; ---------------------------------------------------------------------------
; Two traps, both from the blocks being closures
;
; Write the table's blocks *literally*, where the table is built -- which is
; what a switch statement looks like anyway. Building them in a loop goes wrong
; in one of two ways, and only one of them tells you.
;
; Capturing a temporary of the loop body fails loudly, because the block outlives
; the frame it was written in (ROADMAP 3.1):
;
;   { i:lessOrEqual(#3) }:whileTrue({ | n |
;       n := i. u:atPut(n, { n:mul(#10) }). i := i:add(#1) }).
;   u:at(#2):value
;   ->  block outlived the frame it was written in
;
; Capturing a *global* instead removes the failure and not the mistake. Every
; block reads the same name, and by the time any of them runs it holds the value
; the loop left behind:

v := dictionary:new.
k := #1.
{ k:lessOrEqual(#3) }:whileTrue({ v:atPut(k, { k:mul(#10) }). k := k:add(#1) }).
v:at(#1, { #0 }):value:print.    ; #40
v:at(#2, { #0 }):value:print.    ; #40  -- all three, because k is #4 by now
v:at(#3, { #0 }):value:print.    ; #40

; A block captures a *name*, not the value the name had. This is the
; closure-in-a-loop bug every language with closures has, and nothing here
; protects you from it.

; ---------------------------------------------------------------------------
; Removing

counts:remove("dog"):print.      ; #1 -- what it held
counts:includes("dog"):print.    ; false
counts:size:print.               ; #7

; Removing a key that is not there is an error, like `at`.
;   counts:remove("dog")   ->  no key "dog" to remove

; ---------------------------------------------------------------------------
; What may be a key
;
; Keys are *values*: numbers, strings, symbols, booleans and nil, all of which
; are compared by content, so two keys that look alike are one key.

mixed := dictionary:new.
mixed:atPut(#1, "the integer").
mixed:atPut(1.0, "the float").
mixed:atPut("1", "the string").
mixed:atPut('one, "the symbol").
mixed:size:print.                ; #4 -- none of them equals another
mixed:at(#1):display.            ; the integer
mixed:at(1.0):display.           ; the float

; An array, a block, an object or another dictionary is compared by *identity*,
; so two that look alike would be two different keys. That is the right answer
; for `equals` and a useless one here, so they are refused rather than quietly
; behaving that way:
;
;   mixed:atPut([#1], "nope")
;   ->  'atPut' wants a value for a key, got array -- those are compared by
;       identity, so two that look alike would be two keys

; A dictionary itself is a reference, like an array: two with the same contents
; are two dictionaries.
a := dictionary:new.
b := dictionary:new.
a:equals(b):print.               ; false
a:equals(a):print.               ; true

; Printing shows the contents, in the table's arbitrary order, in angle brackets
; rather than the square ones an array gets -- there is no literal, so it does
; not read back as one.
small := dictionary:new.
small:atPut('only, #1).
small:print.                     ; <dictionary 'only: #1>
