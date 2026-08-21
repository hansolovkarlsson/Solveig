; Arrays hold values. Indices are one-based: an index is an ordinal, not an
; offset into anything.
; Run with:  ./bin/solas examples/arrays.sol && ./bin/solvm examples/arrays.sob

; [...] is sugar for array:of(...) -- the same send, compiled to the same
; instructions, so the two spellings cannot drift apart.
a := [#10, #20, #30].
a:print.                     ; [#10, #20, #30]
a:size:print.                ; #3
a:at(#1):print.              ; #10  -- the first element
a:at(#3):print.              ; #30

; add answers the array, so it chains.
b := [].                     ; an empty array; array:new says the same thing
b:add(#1):add(#2):add(#3).
b:print.                     ; [#1, #2, #3]

; at_put replaces in place and answers the value stored, as ':=' does.
b:at_put(#2, #99).
b:print.                     ; [#1, #99, #3]

; do runs a block per element, in order.
sum := #0.
b:do({ e | sum := sum:add(e) }).
sum:print.                   ; #103

; Arrays are references, like objects: two names, one array.
c := b.
c:at_put(#1, #7).
b:at(#1):print.              ; #7 -- the change is visible through b

; They nest, which is where the brackets earn their keep.
n := [[#1, #2], [#3]].
n:print.                     ; [[#1, #2], [#3]]
n:at(#1):at(#2):print.       ; #2

; A method can build one and answer it.
integer:upto := { | out, i |
    out := array:new.
    i := #1.
    { i:greaterThan(self):not() }:whileTrue({
        out:add(i).
        i := i:add(#1)
    }).
    out
}.

#8:upto:print.               ; [#1, #2, #3, #4, #5, #6, #7, #8]

; collect answers a new array of the block's results; select answers the
; elements the block accepted. Neither changes the array it was sent to.
squares := [#1, #2, #3, #4, #5]:collect({ x | x:mul(x) }).
squares:print.               ; [#1, #4, #9, #16, #25]

[#1, #2, #3, #4, #5]:select({ x | x:greaterThan(#2) }):print.   ; [#3, #4, #5]

; inject folds the array down to one value. The block is given what has
; accumulated so far and one element, and answers the next accumulation.
[#1, #2, #3, #4]:inject(#0, { total, n | total:add(n) }):print.   ; #10
[#2, #3, #4]:inject(#1, { total, n | total:mul(n) }):print.       ; #24

; An empty array answers the start without ever calling the block, so a fold is
; safe to write without asking first whether there is anything to fold.
[]:inject(#0, { total, n | total:add(n) }):print.                 ; #0

; What accumulates need not be the type of the elements.
[#1, #2, #3]:inject("", { s, n | s:concat(n:asString) }):print.   ; "123"

; do throws its answers away; collect and select each answer an array; inject
; answers one value. Unlike do, it is an expression, so it can stand in the
; middle of one rather than only at the top of a frame.
[#1, #2, #3]:inject(#0, { t, n | t:add(n) }):greaterThan(#5):print.   ; true

; They chain, so a pipeline reads left to right.
#10:upto
    :collect({ x | x:mul(x) })
    :select({ x | x:lessThan(#30) })
    :print.                  ; [#1, #4, #9, #16, #25]

; And a pipeline can end in a single value.
#10:upto
    :select({ x | x:mod(#2):equals(#0) })
    :inject(#0, { total, n | total:add(n) })
    :print.                  ; #30

; ---------------------------------------------------------------------------
; Taking a piece of one

; copyFrom includes both ends and both are one-based, exactly as a string's
; does -- two collections disagreeing about what a slice means would be worse
; than either rule is good.
[#1, #2, #3, #4, #5]:copyFrom(#2, #4):print.     ; [#2, #3, #4]
[#1, #2, #3, #4, #5]:copyFrom(#3, #2):print.     ; [] -- one before the start

; Out of range is an error, following `at`:
;   [#1, #2, #3]:copyFrom(#1, #4)
;   ->  'copyFrom' ends at #4, past an array of size 3

; first and last take a quantity rather than positions, and they *clamp*. Asking
; a three-element array for its top five is a question it has answered by
; handing over three -- so a ranked report does not have to check the size.
[#1, #2, #3, #4, #5]:first(#2):print.            ; [#1, #2]
[#1, #2, #3, #4, #5]:last(#2):print.             ; [#4, #5]
[#1, #2, #3]:first(#99):print.                   ; [#1, #2, #3]
[#1, #2, #3]:last(#0):print.                     ; []

; Clamping is for asking for more than there is, not for nonsense:
;   [#1, #2]:first(#0:sub(#1))
;   ->  'first' needs a count of #0 or more, got #-1

; All three answer a new array and leave the receiver alone, like collect,
; select and sorted.

; join puts an array of strings together with a separator between them. It is
; strict: an array holding anything else is an error, rendering being what
; asString and fill are for.
["ada", "grace", "alan"]:join(", "):print.       ; "ada, grace, alan"
["a", "b"]:join(""):print.                       ; "ab"
[]:join(","):print.                              ; ""

; sorted answers a new array, like collect and select -- the receiver is left
; alone. With no block the order comes from *sending* lessThan.
[#3, #1, #2]:sorted:print.                            ; [#1, #2, #3]
["pear", "apple", "fig"]:sorted:print.                ; ["apple", "fig", "pear"]

; A block orders by whatever you like; it answers whether a comes before b.
[#1, #3, #2]:sorted({ a, b | b:lessThan(a) }):print.  ; [#3, #2, #1]

; The sort is stable, so sorting twice orders by two keys -- minor key first,
; then major. Here: by name within each score.
row := { name, score | | r |
    r := object:new. r:name := name. r:score := score. r
}.

rows := [row:value("cara", #2), row:value("abe", #1),
         row:value("bea", #2), row:value("dan", #1)].

rows:sorted({ x, y | x:name:lessThan(y:name) })
    :sorted({ x, y | x:score:lessThan(y:score) })
    :collect({ r | r:name })
    :print.                                           ; ["abe", "dan", "bea", "cara"]
