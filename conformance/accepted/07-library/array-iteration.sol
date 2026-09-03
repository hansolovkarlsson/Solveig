; conformance: do, collect, select and inject are the four iteration messages, and three of them answer
; varies: machine
;
; do throws its answers away, collect and select each answer an array, and inject
; answers one value. All four leave the receiver untouched, and select's block is
; strict about answering a boolean.

[#1, #2, #3]:do({ n | n:print }).
[#1, #2, #3]:collect({ n | n:mul(#2) }):print.
[#1, #2, #3, #4]:select({ n | n:mod(#2):equals(#0) }):print.
[#1, #2, #3, #4]:inject(#0, { total, n | total:add(n) }):print.
[#1, #2, #3]:inject("", { s, n | s:concat(n:asString) }):print.

; An empty array answers start without calling the block, so a fold is safe to
; write without asking first whether there is anything to fold.
[]:inject(#7, { t, n | error:raise("never") }):print.

; do answers the receiver, so it chains.
[#1]:do({ n | nil }):print.

; loop is a counted loop over the bounds rather than the elements, both ends
; included, and answers nil.
total := #0.
[#1, #5]:loop({ i | total := total:add(i) }).
total:print.
[#1, #10, #3]:loop({ i | i:print }).
[#1, #3]:loop({ i | nil }):print.

; repeat is the same idea without a counter.
n := #0.
#3:repeat({ n := n:add(#1) }).
n:print.
