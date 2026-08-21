; control.sol -- loops the language does not have syntax for.
;
;     @include "control.sol".
;
; Found on the search path, so no program has to say where this lives. See
; docs/REFERENCE.md#the-library.
;
; Control flow is message sending, so these are ordinary methods on ordinary
; classes rather than anything the compiler knows about. They are here because
; writing them again in every program is silly, not because they were hard.
;
; This file binds names and does nothing else. A library that printed something
; when you included it would be a poor guest.

; ---------------------------------------------------------------------------
; repeat -- a body n times, counting nothing you care about
;
;     #3:repeat({ "tick":display }).
;     { "tock":display }:repeat(#2).
;
; Both spellings, because which reads better depends on which of the two the
; sentence is about. The second is defined in terms of the first.

integer:repeat := { body | | i |
    i := #0.
    { i:lessThan(self) }:whileTrue({ body:value. i := i:add(#1) }).
    nil
}.

block:repeat := { n | n:repeat(self) }.

; ---------------------------------------------------------------------------
; doUntil is not here any more
;
; It used to be, and it was the most useful thing in this file: the one loop
; `whileTrue` cannot express without a flag declared outside it. That is exactly
; why it was built into the language instead -- written literally it now
; compiles to jumps, which makes it 2.29x the version that lived here and 1.28x
; the hand-written flag loop it replaces. See ROADMAP 6.6.
;
; Defining it here again would be a trap rather than an override: the compiler
; splices the loop in when both blocks are written on the spot, so a definition
; in this file would be bypassed exactly where it was most likely to be wanted.

; ---------------------------------------------------------------------------
; toDo and toByDo -- a counted loop over a range
;
;     #1:toDo(#3, { n | n:display }).            ; 1 2 3
;     #1:toByDo(#10, #3, { n | n:display }).     ; 1 4 7 10
;
; Inclusive at both ends, following `copyFrom` and `at`: an index here is an
; ordinal, and half-open ranges are what make *zero*-based indexing tidy.
;
; A step of #0 would never finish, so it is refused rather than hanging. A
; negative step counts down, and stops when it passes the limit.

integer:toByDo := { limit, step, body | | i |
    i := self.
    step:equals(#0):ifElse(
        { "toByDo needs a step other than #0, and was given one":display },
        { step:greaterThan(#0):ifElse(
            { { i:lessOrEqual(limit) }:whileTrue({ body:value(i). i := i:add(step) }) },
            { { i:greaterOrEqual(limit) }:whileTrue({ body:value(i). i := i:add(step) }) }) }).
    nil
}.

integer:toDo := { limit, body | self:toByDo(limit, #1, body) }.

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
