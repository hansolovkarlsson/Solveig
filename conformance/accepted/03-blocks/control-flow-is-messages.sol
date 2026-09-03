; conformance: ifTrue, ifElse, whileTrue, and and or are ordinary messages taking blocks
; varies: machine
;
; Written literally they compile to jumps, which is an optimisation and not a
; second meaning: a block reached through a name is still a block, and the same
; program written that way answers the same thing. Both forms are here, because
; only one of them is what a machine implements.

#5:lessThan(#10):ifTrue({ "small":display }).
#5:lessThan(#10):ifElse({ "small" }, { "large" }):display.
#5:greaterThan(#10):ifTrue({ "never":display }):print.

i := #0.
{ i:lessThan(#5) }:whileTrue({ i := i:add(#1) }).
i:print.

; The same, with every block held in a name, so nothing is inlined.
cond := { i:greaterThan(#0) }.
body := { i := i:sub(#1) }.
cond:whileTrue(body).
i:print.

x := #3.
c := { x:lessThan(#10) }.
x:greaterThan(#0):and(c):print.
x:greaterThan(#0):or(c):print.

; and and or stop early, so the block is not run when the answer is settled.
ran := false.
watch := { ran := true. true }.
false:and(watch):print.
ran:print.
true:or(watch):print.
ran:print.

; doUntil runs its body before testing, which is the loop whileTrue cannot write.
n := #0.
{ n := n:add(#1) }:doUntil({ n:greaterOrEqual(#3) }).
n:print.
