; conformance: a block reads the frame it was written in, lexically, however many blocks deep
; varies: machine

integer:sumTo := { | total, i |
    total := #0.
    i := #1.
    { i:greaterThan(self):not }:whileTrue({
        total := total:add(i).
        i := i:add(#1)
    }).
    total
}.
#10:sumTo:print.

; Three deep, reading the outermost frame's temporary.
outer := { | t |
    t := #1.
    { { { t:add(#1) }:value:add(#1) }:value:add(#1) }:value
}.
outer:value:print.

; A block writes the frame it captured, so the change is visible after it runs.
counter := { | n |
    n := #0.
    [#1, #2, #3]:do({ e | n := n:add(e) }).
    n
}.
counter:value:print.

; 'self' is the receiver the block was written under, captured when the block is
; made -- so a block inside a method still answers the right object.
integer:doubledLater := { { self:mul(#2) } }.
#21:doubledLater:value:print.
