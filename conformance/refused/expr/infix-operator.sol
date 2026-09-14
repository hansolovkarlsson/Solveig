; conformance: an infix operator is refused rather than parsed
; varies: front
; refused: expr/infix-operator
;
; The language has no operators. A '+' met where a send was expected is not a
; send and not a name, and saying so at the point it appears is what stops it
; being read as two statements. The @expr region, where a front end has one,
; is off unless asked for -- see region-off.sol -- so this holds with or
; without it.

x := #1 + #2.
x:print.
