; The example from the original design notes, in the settled syntax.
; Run it with:  ./bin/solis < examples/hello.sol

a := #45.
a:print.

; `#` picks the type: #45 is an integer, a bare 45 is a float.
i := #45.
f := 45.
i:print.
f:print.

; integer:new is the explicit long form of the literal.
b := integer:new(#45).
b:print.

; Values are immutable -- add returns a new one and leaves `a` alone.
a:add(#5):print.
a:print.

; Sends chain left to right, so this is (2+3)*4.
#2:add(#3):mul(#4):print.
