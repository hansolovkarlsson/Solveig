; A block is code as a value: writing { ... } runs nothing.
; Run with:  ./bin/solas examples/blocks.sol && ./bin/solum examples/blocks.sob

; Control flow is ordinary message sending. `ifTrue` receives an unevaluated
; block and decides whether to run it -- nothing in the compiler knows it.
true:ifTrue({ #1:print }).                              ; #1
false:ifFalse({ #2:print }).                            ; #2

#5:lessThan(#10):ifElse({ #100:print }, { #200:print }).  ; #100

; A block is a value, so it can be stored and run later.
b := { #21:add(#21) }.
b:value():print.                                        ; #42

; Conditionals plus recursion give a recursion that terminates.
integer:factorial() := (
    self:lessThan(#2):ifElse(
        { #1 },
        { self:mul( self:sub(#1):factorial() ) }
    )
).

#5:factorial():print.                                   ; #120
#20:factorial():print.                                  ; #2432902008176640000

; whileTrue re-runs its receiver every pass, which is exactly why the condition
; has to be a block and not a value.
integer:sumTo() := (
    total := #0.
    i := #1.
    { i:greaterThan(self):not() }:whileTrue({
        total := total:add(i).
        i := i:add(#1)
    }).
    total
).

#100:sumTo():print.                                     ; #5050

; A block written inside a method reads that method's locals and its `self`,
; even though whileTrue is what actually runs it.
integer:doubled() := { self:mul(#2) }:value().
#21:doubled():print.                                    ; #42
