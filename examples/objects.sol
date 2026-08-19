; There is no separate notion of a class. An object is a bag of slots with a
; prototype it delegates to, and `new` answers a fresh object delegating to the
; receiver. Whether something is a class or an instance is how you use it.
; Run with:  ./bin/solas examples/objects.sol && ./bin/solum examples/objects.sob

point := object:new.

; Slots on the prototype are defaults every instance sees.
point:x := #0.
point:y := #0.

; A method is just a slot holding a block; `self` is whoever was sent to.
point:sum := { self:x:add(self:y) }.
point:show := { self:x:print. self:y:print }.

; A constructor is an ordinary method. `self:new` rather than `point:new`, so it
; keeps working for anything that inherits it.
point:make := { a, b | | p |
    p := self:new.
    p:x := a.
    p:y := b.
    p
}.

p := point:make(#3, #4).
p:sum:print.                 ; #7

; Assigning on an instance makes the instance's own slot, so it shadows the
; prototype rather than writing through to it.
q := point:new.
q:sum:print.                 ; #0 -- q still sees the defaults

; Delegation chains, and the nearest slot wins.
animal := object:new.
animal:name := "animal".
animal:speak := { "..." }.
animal:describe := { self:name:concat(" says "):concat(self:speak) }.

dog := animal:new.
dog:name := "dog".
dog:speak := { "woof" }.

rex := dog:new.
rex:name := "rex".

animal:describe:print.       ; "animal says ..."
dog:describe:print.          ; "dog says woof"
rex:describe:print.          ; "rex says woof" -- describe from animal,
                             ;                   speak from dog, name from rex

; Equality is identity: two objects with the same slots are still two objects.
point:make(#1, #2):equals(point:make(#1, #2)):print.   ; false
