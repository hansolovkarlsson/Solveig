; conformance: sends chain strictly left to right, and parentheses are the only way to redirect one
; varies: both
;
; There are no operators outside an @expr region and so no precedence to
; remember. `#2:add(#3):mul(#4)` is (2+3)*4 because each send takes the previous
; answer as its receiver, and a formula that needs another shape says so with a
; group.

#2:add(#3):mul(#4):print.
#1:add(#2):mul(#3):print.
#1:add((#2:mul(#3))):print.

; A group holds several statements, discards all but the last, and answers it.
( #1. #2 ):print.

; Chaining works on any receiver, not only a number.
"a":concat("b"):concat("c"):asUppercase:display.
[#3, #1, #2]:sorted:first(#2):print.
