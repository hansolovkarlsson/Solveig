; Reflection -- asking an object what it is and what it understands.
; Run:  solas examples/reflect.sol -o reflect.sob && solvm reflect.sob

point := object:new.
point:x := #0.
point:y := #0.
point:show := {
    "(":concat(self:x:asString):concat(", "):concat(self:y:asString):concat(")")
}.

; What does an object hold? The names come back in the order they were defined.
point:slots:print.               ; ['x, 'y, 'show]

p := point:new.
p:x := #3.
p:y := #4.

; Own slots only -- `show` belongs to the parent, and `parent:slots` asks it.
p:slots:print.                   ; ['x, 'y]
p:parent:slots:print.            ; ['x, 'y, 'show]

; Where does it come from?
p:isKindOf(point):print.         ; true
p:isKindOf(object):print.        ; true
#45:isKindOf(integer):print.     ; true -- a value answers for its class

; Would a send of that name land? Inherited and built-in names both count.
p:respondsTo('show):print.       ; true
p:respondsTo('area):print.       ; false
#45:respondsTo('add):print.      ; true

; A name decided at run time rather than written down.
p:perform('show):display.        ; (3, 4)

; Which is what lets a table of names stand in for a chain of branches.
describe := { o |
    o:slots:collect({ name |
        name:asString:concat(" = "):concat(o:perform(name):asString)
    })
}.
describe:value(p):print.         ; ["x = 3", "y = 4"]

; And it makes the built-in classes describable too -- they are objects whose
; slots happen to be primitives.
integer:slots:size:print.

; A slot holding a block is a method, so slotAt is the only way to hold one as
; a value. What comes back is the plain block: `self` is supplied by a send, so
; a fetched method has none until you give it one.
m := point:slotAt('show).
;   m:value.                     ; solvm: nil does not understand 'x'

; `boundTo` gives it one, answering a second block over the same code. Binding
; and calling stay two things, the way `via` keeps them two things -- so `value`
; means what it always meant.
m:boundTo(p):value:display.      ; (3, 4)

; Which means the arguments are still the block's own, with the receiver
; nowhere among them.
integer:poly := { a, b | self:mul(a):add(b) }.
integer:slotAt('poly):boundTo(#10):value(#3, #7):print.   ; #37

; Binding answers a new block and leaves the original alone, so one fetched
; method can be bound to each of several receivers in turn.
q := point:new. q:x := #10. q:y := #20.
[p, q]:collect({ e | m:boundTo(e):value }):print.   ; ["(3, 4)", "(10, 20)"]

; Two things binding does not do. It does not lift the frame restriction -- a
; block that reads its home frame is no freer for being bound. And it does not
; survive a send: an installed block is an ordinary method, and a send supplies
; its own receiver, which is what makes it one.
other := object:new. other:x := #100. other:y := #1.
other:show := m:boundTo(p).
other:show:display.              ; (100, 1) -- the send wins, not the binding
