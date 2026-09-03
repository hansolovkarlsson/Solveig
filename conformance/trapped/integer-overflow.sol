; conformance: integer arithmetic traps on overflow rather than wrapping
; varies: machine
; status: nonzero
;
; A machine that wraps answers a number here rather than stopping, and the
; program that asked would carry on with it. The .out beside this case is what
; must have been printed by the time it stops.

#9223372036854775806:add(#1):print.
#9223372036854775807:add(#1):print.
