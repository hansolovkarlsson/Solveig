; conformance: '.' separates statements, and a line opening with ':' continues
; varies: front
;
; A '.' only continues a number when a digit follows it, so `45.` is the float 45
; and then a separator. A line beginning with ':' continues the expression above
; it, so the two lines below are one statement rather than two.

x := 45. x:print.

total := #10
:add(#5).
total:print.

; The separator is required between two statements and optional after the last,
; in a script and inside a group alike.
( #1. #2 ):print.
