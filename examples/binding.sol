; binding.sol -- names, statements, groups, and temporaries.
; Run with:  ./bin/solas examples/binding.sol && ./bin/solvm examples/binding.sob
;
; The plumbing every other example uses without stopping to look at it.

; ---------------------------------------------------------------------------
; ':=' binds a name, and it is one operator everywhere

greeting := "hi".                       ; a global
integer:double := { self:mul(#2) }.     ; a slot on the integer class

greeting:display.                       ; hi
#21:double:print.                       ; #42

; Those are the same operation. A slot holding a block is what makes a method;
; nothing marks one as different from a name holding a string.

; The right-hand side is evaluated first, and *because* it is, a method can be
; computed rather than written out. Nothing was added to the language to allow
; this -- it falls out of ':=' meaning one thing.
maker := { { self:mul(#3) } }.
integer:triple := maker:value.
#7:triple:print.                        ; #21

; Binding answers the value it bound, so this chains and means what it looks
; like it means.
a := b := #5.
a:print.                                ; #5
b:print.                                ; #5

; ---------------------------------------------------------------------------
; '.' separates statements rather than terminating them
;
; Required between two, optional after the last. A line beginning with ':'
; continues the expression above it, so this is one statement:

total := #10
    :add(#5)
    :mul(#2).
total:print.                            ; #30

; ---------------------------------------------------------------------------
; A group runs an expression and answers its last statement

(#1:add(#2)):mul(#10):print.            ; #30 -- (1+2)*10
#1:add((#2:mul(#3))):print.             ; #7  -- 1+(2*3)

; It may hold several statements. The earlier ones are discarded.
( #1. #2. #3 ):print.                   ; #3

; ---------------------------------------------------------------------------
; Temporaries are declared between pipes, and belong to a frame
;
; A block makes a frame, so a block may declare them.

average := { | total |
    total := #0.
    [#1, #2, #3, #4]:do({ e | total := total:add(e) }).
    total:div(#4)
}.
average:value:print.                    ; #2

; A group borrows the frame it sits in rather than making one, which is why a
; group inside a block may declare temporaries too -- and why one at the top
; level of a script cannot. There is no frame there to put them in.
;
;   #1:add(( | t | t := #5. t )).
;   [line 1:10] solas: a temporary needs a frame, so declare it inside a block at '|'

inside := { ( | t | t := #5. t:add(#1) ) }.
inside:value:print.                     ; #6

; Assignment inside a block will not quietly create a global either, so a typo
; cannot bring a name into being where it would look like a local.
;
;   { undeclared := #1 }:value.
;   solvm: undefined name 'undeclared' -- declare it with '| undeclared |'
;          or assign it at the top level
