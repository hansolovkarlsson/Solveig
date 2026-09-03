; conformance: integer division and remainder trap on a zero divisor
; varies: machine
; status: nonzero
;
; A float divided by zero answers infinity, which is IEEE. An integer has no
; such value to answer with, so it stops.

#7:div(#2):print.
0:div(0):print.
#7:div(#0):print.
