; conformance: a slot holding a block is a method, and one holding anything else answers that value
; varies: machine
;
; Sending a method's name runs it with the receiver as 'self'. That is the whole
; distinction: there is no declaration saying which slots are methods.

point := object:new.
point:x := #0.
point:y := #0.
point:sum := { self:x:add(self:y) }.

point:make := { a, b | | p |
    p := self:new.               ; self, so it survives inheritance
    p:x := a.
    p:y := b.
    p
}.

p := point:make(#3, #4).
p:sum:print.

; A slot holding a block answers by running; a slot holding a block-shaped value
; reached with slotAt answers the block itself.
p:slotAt('sum):print.

; 'make' used self, so a prototype further down inherits it and still makes one
; of its own kind.
point3 := point:new.
point3:z := #0.
point3:sum := { self:via(point):sum:add(self:z) }.
q := point3:make(#1, #2).
q:z := #10.
q:sum:print.
q:isKindOf(point):print.
q:isKindOf(point3):print.
p:isKindOf(point3):print.
