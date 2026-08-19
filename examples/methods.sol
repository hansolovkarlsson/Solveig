; A method is a name bound on a class, exactly as a variable is a name bound in
; the globals -- so it uses the same ':=', and the right-hand side is evaluated.
; A slot holding a block is what makes a method.
;
; Run with:  ./bin/solas examples/methods.sol && ./bin/solvm examples/methods.sob

integer:double := { self:mul(#2) }.

#21:double:print.          ; #42

; Parameters come before '|'.
integer:poly := { a, b | self:mul(a):add(b) }.

#10:poly(#3, #7):print.    ; #37

; A leading '|' declares temporaries instead. Only these and the parameters are
; locals; every other name is a global.
integer:quadruple := { | d |
    d := self:double.
    d:double
}.

#3:quadruple:print.        ; #12

; Sends chain, so calls nest.
#5:double:double:print.    ; #20

; A method reaches the globals, and may update them.
offset := #100.
integer:shifted := { self:add(offset) }.

#5:shifted:print.          ; #105

; A slot holding anything other than a block is data: evaluated once when bound,
; then simply answered.
integer:limit := #45:add(#32).

#1:limit:print.            ; #77

; Because ':=' evaluates, a method can be computed rather than written out.
maker := { { self:mul(#3) } }.
integer:triple := maker:value().

#14:triple:print.          ; #42
