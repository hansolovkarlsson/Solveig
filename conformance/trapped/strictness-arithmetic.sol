; conformance: the two numeric types never combine, so a float argument to integer arithmetic stops
; varies: machine
; status: nonzero
;
; A machine that coerced would answer 3.5 here. The conversion is written out or
; it does not happen.

#2:add(#3):print.
#2:asFloat:add(1.5):print.
#2:add(1.5):print.
