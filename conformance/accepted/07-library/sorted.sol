; conformance: sorted answers a new array, ascending, and sorted(block) orders by the block
; varies: machine
;
; The receiver is untouched by both. With no block the comparison is `lessThan`,
; which is why an array of symbols sorts and an array of mixed types does not.

a := [#3, #1, #2].
a:sorted:print.
a:print.

[2.5, 1.5, 3.5]:sorted:print.
["pear", "apple", "fig"]:sorted:print.

; With a block, the block says what comes first, and it is strict about
; answering a boolean.
[#3, #1, #2]:sorted({ x, y | x:greaterThan(y) }):print.

; Ordering by something other than the element itself is the case a block is for.
["ccc", "a", "bb"]:sorted({ x, y | x:size:lessThan(y:size) }):print.

[]:sorted:print.
[#1]:sorted:print.
