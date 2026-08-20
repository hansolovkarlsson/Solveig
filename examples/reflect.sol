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
