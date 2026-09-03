; conformance: a file that includes itself compiles, and the include does nothing
; varies: front
; stderr: expected
;
; **This is a warning and not a refusal**, which is worth a case because the
; producer's contract lists it in a table beside two rules that *are* refusals.
; The file compiles, leaves with 0, and runs -- so what a second front end must
; get right here is not rejecting the program but noticing the cycle and
; carrying on. One that followed the include would not stop.
;
; What it says while doing that is its own business, which is why this case
; declares that something is expected on standard error and does not compare it.

@include "self-include.sol".
#1:print.
