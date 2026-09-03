; conformance: floats follow IEEE-754, so dividing by zero answers a value rather than failing
; varies: machine
;
; Integer arithmetic traps where float arithmetic reaches infinity and nan,
; those being representable floats where there is no such integer. nan is not
; equal to itself, which is IEEE rather than a choice made here.

1:div(0):print.
0:sub(1):div(0):print.
0:div(0):print.
nan:equals(nan):print.
infinity:print.
0:sub(1):sqrt:print.

2:sqrt:print.
1:div(3):print.

; A float is written as the shortest text that reads back as the same value.
0.1:print.
1e21:print.
0.000001:print.

; The narrowing messages name their direction, so there is no default to
; remember, and rounding is half away from zero.
2.5:rounded:print.
0:sub(2.5):rounded:print.
2.7:floor:print.
2.2:ceiling:print.
0:sub(2.7):truncated:print.
