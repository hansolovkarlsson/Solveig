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

; They chain, so a pipeline reads left to right.
#10:upto
    :collect({ x | x:mul(x) })
    :select({ x | x:lessThan(#30) })
    :print.                  ; [#1, #4, #9, #16, #25]

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
