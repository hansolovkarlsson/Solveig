; conformance: object:new answers a fresh object delegating to the receiver, and the nearest slot wins
; varies: machine
;
; There is no separate notion of a class. Whether something is a class or an
; instance is how you use it, and assigning on an instance always makes the
; instance's own slot -- so it shadows the prototype rather than writing through.

point := object:new.
point:x := #0.
point:y := #0.

p := point:new.
p:x:print.
p:x := #3.
p:x:print.
point:x:print.

; Delegation chains, and the nearest slot wins at every depth.
a := object:new. a:tag := #1.
b := a:new.
c := b:new.
c:tag:print.
b:tag := #2.
c:tag:print.
c:tag := #3.
c:tag:print.
a:tag:print.

; 'slots' answers own slots, in the order they were defined. Inherited names are
; not yours, which is what makes the answer a fact about this object.
point:slots:print.
p:slots:print.
c:parent:equals(b):print.
