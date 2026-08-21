; control.sol -- what is left that the language does not have.
;
;     @include "control.sol".
;
; Found on the search path, so no program has to say where this lives. See
; docs/REFERENCE.md#the-library.
;
; This file is nearly empty, and that is the record of something rather than an
; oversight: it opened with five loops in it, four were measured, and all four
; were worth building into the VM. What is left is the one nobody has measured.
;
; The machinery around it -- the search path, `@include` finding a name it was
; not told the location of -- is what matters and is unchanged. This is where
; the next thing goes.
;
; This file binds names and does nothing else. A library that printed something
; when you included it would be a poor guest.

; ---------------------------------------------------------------------------
; repeat, toDo and toByDo are not here any more
;
; Nor is doUntil. All four started in this file, written in Solum, and all four
; turned out to be worth building into the VM -- which is what ROADMAP 6.6 was
; asking, though it expected the answer to be compiler inlining rather than
; primitives. Measured, a primitive `repeat` is 3.2x the version that lived here
; and 2.5x what inlining would have produced: inlining removes the block call
; per iteration and keeps two bytecode sends for the counter, where a primitive
; removes the two sends and keeps the block call. The sends cost more.
;
; Defining any of them here again would be a trap rather than an override. A
; slot bound on `integer` shadows the primitive, so the slow version would
; quietly win -- and for doUntil the compiler splices the loop in anyway, so a
; definition would be bypassed exactly where it was most wanted.

; ---------------------------------------------------------------------------
; timesCollect -- n results, gathered
;
;     #4:timesCollect({ n | n:mul(n) }):print.   ; [#1, #4, #9, #16]
;
; `collect` maps an array that already exists; this makes one. The block is
; given the number of the pass, one-based, like every other index here.

integer:timesCollect := { body | | out, i |
    out := array:new.
    i := #1.
    { i:lessOrEqual(self) }:whileTrue({ out:add(body:value(i)). i := i:add(#1) }).
    out
}.
