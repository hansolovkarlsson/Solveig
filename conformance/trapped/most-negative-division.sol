; conformance: the most negative integer divided by minus one traps
; varies: machine
; status: nonzero
;
; The one division that overflows rather than dividing by zero: the result is
; one past the largest integer there is.

x := #-9223372036854775807:sub(#1).
x:print.
x:div(#-1):print.
