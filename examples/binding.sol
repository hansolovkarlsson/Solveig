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

; A group borrows the frame it sits in rather than making one, so its
; temporaries belong to that frame. The script has a frame too, so this works at
; the top level as readily as inside a block:
#1:add(( | t | t := #5. t )):print.     ; #6

inside := { ( | u | u := #5. u:add(#1) ) }.
inside:value:print.                     ; #6

; The whole script is one frame, though, so two groups in a file share a
; namespace: declaring `t` again above would be an error, the same way two
; groups inside one block cannot both declare it.

; Assignment inside a block will not quietly create a global either, so a typo
; cannot bring a name into being where it would look like a local.
;
;   { undeclared := #1 }:value.
;   solvm: undefined name 'undeclared' -- declare it with '| undeclared |'
;          or assign it at the top level
