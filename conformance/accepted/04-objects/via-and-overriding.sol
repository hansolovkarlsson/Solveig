; conformance: self:via(ancestor) starts the lookup there and keeps the receiver
; varies: machine
;
; The ancestor is named rather than inferred, so a method extends the object it
; was written against however deep the receiver is, and 'self' inside the
; ancestor's method is still the instance.

animal := object:new.
dog := animal:new.

animal:intro := { "I am ":concat(self:name) }.
dog:intro := { self:via(animal):intro:concat("!") }.

rex := dog:new. rex:name := "rex".
rex:intro:display.

; 'parent' reads the delegation link and is read-only. Assigning it binds an
; ordinary slot that shadows the message -- the assignment succeeds, the slot
; answers, and the chain is unchanged. It is the one assignment that looks like
; it did something and did not.
a := object:new. a:tag := #1.
b := object:new. b:tag := #2.
kid := a:new.

kid:parent := b.
kid:parent:equals(b):print.
kid:tag:print.
