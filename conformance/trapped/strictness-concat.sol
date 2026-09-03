; conformance: concat is strict about its argument being a string
; varies: machine
; status: nonzero
;
"a":concat("b"):display.
"a":concat(#1:asString):display.
"a":concat(#1):display.
