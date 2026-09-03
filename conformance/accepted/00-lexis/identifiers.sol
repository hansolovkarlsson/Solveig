; conformance: an identifier is [A-Za-z_][A-Za-z0-9_]*, and none of the bound names is a keyword
; varies: front
;
; There are no reserved words. `nil`, `true`, `object` and `self` are ordinary
; identifiers that happen to be bound -- which is why a front end built from the
; grammar alone accepts programs the compiler refuses, and why those refusals are
; a separate corpus from this one.

_x := #1.
x_1 := #2.
Camel_9 := #3.
_x:add(x_1):add(Camel_9):print.

; A selector is an identifier too, which is why '=' cannot be one: `a:=(b)` would
; otherwise be both an assignment and a send.
#7:asString:display.
