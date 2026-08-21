; A block is code as a value: writing { ... } runs nothing.
; Run with:  ./bin/solas examples/blocks.sol && ./bin/solvm examples/blocks.sob

; Control flow is ordinary message sending. `ifTrue` receives an unevaluated
; block and decides whether to run it -- nothing in the compiler knows it.
true:ifTrue({ #1:print }).                                ; #1
false:ifFalse({ #2:print }).                              ; #2

#5:lessThan(#10):ifElse({ #100:print }, { #200:print }).  ; #100

; A block is a value, so it can be stored, passed, and run later.
b := { #21:add(#21) }.
b:value():print.                                          ; #42

; ---------------------------------------------------------------------------
; A group is not a block
;
; Both are code in brackets. A group runs where it is written and answers its
; last statement; a block runs nowhere until something sends it `value`.

m := { x | x:add(#1) }.
(m:value(#42)):print.                                     ; #43     -- it ran
{ m:value(#42) }:print.                                   ; <block> -- it did not
{ m:value(#42) }:value:print.                             ; #43     -- now it did

; Which is the whole of why control flow above works. An argument is evaluated
; before the send, like any other argument, so a group would have run before
; `ifTrue` could decide anything about it.
false:ifTrue(("the group ran anyway":display. nil)).
false:ifTrue({ "the block did not":display }).

; A block makes a frame; a group borrows the one it is in. So a group's
; temporaries are the enclosing block's -- and a group may only declare them
; where there is a frame to declare them in.
{ | a |
    a := #1.
    ( a := a:add(#1). a )                                 ; the same `a`
}:value:print.                                            ; #2

; Parameters come before '|'.
add := { a, b | a:add(b) }.
add:value(#3, #4):print.                                  ; #7

; Conditionals plus recursion give a recursion that terminates.
integer:factorial := {
    self:lessThan(#2):ifElse(
        { #1 },
        { self:mul( self:sub(#1):factorial ) }
    )
}.

#5:factorial:print.                                       ; #120
#20:factorial:print.                                      ; #2432902008176640000

; whileTrue re-runs its receiver every pass, which is exactly why the condition
; has to be a block and not a value. The blocks reach out to `total` and `i` in
; the frame that wrote them.
integer:sumTo := { | total, i |
    total := #0.
    i := #1.
    { i:greaterThan(self):not() }:whileTrue({
        total := total:add(i).
        i := i:add(#1)
    }).
    total
}.

#100:sumTo:print.                                         ; #5050

; `self` is the receiver the block was written under, so a block inside a method
; still answers the right object.
integer:doubled := { { self:mul(#2) }:value() }.
#21:doubled:print.                                        ; #42

; Written literally, `ifElse` and `whileTrue` compile to jumps: no block is
; allocated and no frame entered. It is an optimisation and nothing more -- the
; same loop reached through variables is an ordinary send, and has to agree.
countTo := { | i, seen |
    i := #0.
    seen := #0.
    { i:lessThan(#5) }:whileTrue({ i := i:add(#1). seen := seen:add(i) }).
    seen
}.

sentCountTo := { | i, seen, condition, body |
    i := #0.
    seen := #0.
    condition := { i:lessThan(#5) }.
    body := { i := i:add(#1). seen := seen:add(i) }.
    condition:whileTrue(body).
    seen
}.

countTo:value:print.                                      ; #15
sentCountTo:value:print.                                  ; #15

; `and` and `or` take a block for the same reason `ifTrue` does: so the answer
; can be settled without running it. The block runs only when the receiver has
; not already decided the question.
x := #3.
x:greaterThan(#0):and({ x:lessThan(#10) }):print.         ; true
x:lessThan(#0):or({ x:equals(#3) }):print.                ; true

; Short-circuit, and here is the proof: the receiver settles both of these, so
; neither block runs and neither `add` happens.
log := array:of().
false:and({ log:add(#1). true }).
true:or({ log:add(#2). false }).
log:size:print.                                           ; #0

; These inline to jumps too, and the same rule decides it: written on the spot,
; no parameters, no temporaries. Reached through a variable it is an ordinary
; send, and the two must agree.
sentAnd := { | c |
    c := { x:lessThan(#10) }.
    x:greaterThan(#0):and(c)
}.
sentAnd:value:print.                                      ; true

; What the block answers is what `and` answers, so it has to be a boolean --
; the same strictness `whileTrue` has about its condition.
;   true:and({ #5 }).
;   solvm: 'and' expects the block to answer a boolean, got integer
