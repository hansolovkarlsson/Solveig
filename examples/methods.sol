; Methods are defined with ':=', the same operator that binds a name.
; Run with:  ./bin/solas examples/methods.sol && ./bin/solum examples/methods.sob

; A single-expression body. `self` is the receiver.
integer:double() := self:mul(#2).

#21:double():print.        ; #42

; Parameters become locals of the method's frame.
integer:poly(a, b) := self:mul(a):add(b).

#10:poly(#3, #7):print.    ; #37

; Parentheses group several statements; the last one is the result.
integer:quadruple() := (
    d := self:double().
    d:double()
).

#3:quadruple():print.      ; #12

; Sends chain, so calls nest.
#5:double():double():print.  ; #20

; A method sees the globals for anything that is not one of its locals.
offset := #100.
integer:shifted() := self:add(offset).

#5:shifted():print.        ; #105
