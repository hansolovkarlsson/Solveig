; conformance: a block is code as a value, and writing one runs nothing
; varies: machine
;
; Parameters come before '|'. A leading '|' declares temporaries, and a block may
; have both -- the parameters, then a temporaries list of its own. The body's
; last statement is the block's answer.

b := { #21:add(#21) }.
b:value:print.
b:value():print.

add := { a, b | a:add(b) }.
add:value(#3, #4):print.

{ | t | t := #5. t:add(#1) }:value:print.

both := { k | | t | t := k:add(#1). t:mul(#2) }.
both:value(#3):print.

; Several statements, and the last is the value.
{ #1. #2. #3 }:value:print.

; Writing one runs nothing, which is what makes it an argument control flow can
; take. A group in the same place would have run before the send.
{ #1:add(#2) }:print.
( #1:add(#2) ):print.
