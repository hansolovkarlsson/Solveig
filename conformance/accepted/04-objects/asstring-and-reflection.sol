; conformance: an object's own asString serves print, display, fill and an enclosing array alike
; varies: machine
;
; Without one an object shows its address, which is why no case here prints a
; bare object: an address is not an answer a second implementation could match.
; Defining asString is how an object becomes printable, and it is the ordinary
; shadowing rule rather than a hook -- a slot always wins over a primitive of the
; same name.

point := object:new.
point:x := #0.
point:y := #0.
point:sum := { self:x:add(self:y) }.
point:asString := { "point({}, {})":fill([self:x, self:y]) }.

p := point:new. p:x := #3. p:y := #4.
p:print.
p:display.
[p]:print.
"here: {}":fill([p]):display.

; The six reflection messages read either side of the class line.
p:sum:print.
p:perform('sum):print.
p:respondsTo('sum):print.
p:respondsTo('nope):print.
p:isKindOf(point):print.
p:slots:print.
p:slotAt('x):print.

; slotAt searches the chain as a send does, so an inherited slot answers.
p:slotAt('y):print.
point:slots:print.
