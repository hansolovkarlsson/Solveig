; dictionaries.sol -- values kept under keys, found by hashing.
; Run with:  ./bin/solas examples/dictionaries.sol && ./bin/solvm examples/dictionaries.sob

; There is no literal for a dictionary the way [#1, #2] is one for an array.
; `new` makes an empty one, and it is one of only two classes that construct --
; a dictionary is mutable, so there is a fresh distinct one to hand back.
ages := dictionary:new.
ages:size:print.                 ; #0

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

; A word appearing more than once, found by asking the pairs.
repeated := array:new.
counts:keysAndValuesDo({ word, n |
    n:greaterThan(#1):ifTrue({ repeated:add(word) })
}).
repeated:sorted:print.           ; ["fox", "the"]

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
