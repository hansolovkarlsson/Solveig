; conformance: a block that touches nothing outside itself may outlive the frame it was written in
; varies: machine
;
; The other half of the rule is a refusal -- a block that reads or writes its
; enclosing frame is reported rather than left to read whatever now sits there --
; and belongs to the corpus of refusals this suite does not yet have. What is
; pinned here is that the permitted half really is permitted, since an
; implementation that kept every frame alive would pass a corpus of refusals and
; still be wrong about this.

make := { { #42 } }.
b := make:value.
b:value:print.

; A block held in a slot, called long after the frame that made it is gone.
holder := object:new.
build := { holder:fn := { "from a frame that has returned" } }.
build:value.
holder:fn:display.

; Parameters are the block's own, so a block using only them escapes too.
adder := { { a, b | a:add(b) } }:value.
adder:value(#20, #22):print.

; And a block is a value: it can go in an array, come back out, and run.
fns := [{ #1 }, { #2 }, { #3 }].
fns:collect({ f | f:value }):print.
