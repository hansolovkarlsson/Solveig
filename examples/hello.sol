; The example from the original design notes, in the settled syntax.
; Run it with:  ./bin/solis < examples/hello.sol

a := #45.
a:print.

; `#` picks the type: #45 is an integer, a bare 45 is a float.
i := #45.
f := 45.
i:print.
f:print.

; The design notes this example comes from had you construct a number and then
; fill it in:
;
;     integer:new(a)
;     a:set(#45)
;
; Neither message exists. Numbers became immutable unboxed values, so there is
; nothing to construct and nothing to fill -- the literal is the whole of it.
; `integer:new` says so rather than quietly answering its own argument, which is
; what it used to do:
;
;   integer:new(#45)  ->  an integer is written #45, and there is nothing for
;                         'new' to make -- #0 is the empty one

; Values are immutable -- add returns a new one and leaves `a` alone.
a:add(#5):print.
a:print.

; Sends chain left to right, so this is (2+3)*4.
#2:add(#3):mul(#4):print.
