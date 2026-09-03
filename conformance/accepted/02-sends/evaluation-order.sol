; conformance: the receiver is evaluated first, then the arguments left to right
; varies: machine
;
; A second implementation has to pick an order, and a program can tell whenever
; an argument has an effect. It holds all the way down: a nested send finishes
; before the next argument begins, `[...]` is its `array:of`, and `#[...]` runs
; each pair's key and then its value, pair by pair.

seen := [].
integer:mark := { seen:add(self). self }.

array:of(#1:mark, #2:mark, #3:mark):size:print.
seen:print.

; The receiver came first, which is the half a left-to-right rule does not say.
seen := [].
#1:mark:add(#2:mark):print.
seen:print.

seen := [].
[#1:mark, #2:mark]:size:print.
seen:print.

seen := [].
#["a" = #1:mark, "b" = #2:mark]:size:print.
seen:print.

; Depth first: the nested send is finished before the next argument is begun.
seen := [].
array:of(#1:mark:add(#2:mark), #3:mark):size:print.
seen:print.

; An @expr region lowers to these same sends and compiles to the same bytes, so
; the two forms could not differ.
seen := [].
@expr( #1:mark + #2:mark * #3:mark ):print.
seen:print.

seen := [].
#1:mark:add(#2:mark:mul(#3:mark)):print.
seen:print.

; The exception is a block, which is not evaluated at all until something sends
; it 'value' -- however far left it sits.
seen := [].
false:and({ #9:mark:equals(#9) }):print.
seen:print.
