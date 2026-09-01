; vectors.pro -- a module that declares its own arithmetic.
;
; Solveig has no operators. Everything is a message send, and `#2:add(#3)` is
; how a sum is written -- which is exact, and which is why lib/text.sol over
; there carries a note saying the shift-and-mask version of its UTF-8 encoder
; "is nothing like what it means". See examples/utf8.pro for that same code
; written twice.
;
; The seven lines below are this module's whole grammar. They hold for this file
; and no other. A second file in the same program may declare `+` to mean
; something else, or not declare it at all, and neither file has to know.

@language solveig.

@infix  +   60 add.
@infix  -   60 sub.
@infix  *   70 mul.
@infix  /   70 div.
@infix  <   40 lessThan.
@infix  >   40 greaterThan.
@prefix ~      not.

; Precedence is the number, and higher binds tighter. Nothing here is built in:
; `*` binds tighter than `+` because this file said 70 and 60.
a := #2 + #3 * #4.
a:print.                          ; #14

((#2 + #3) * #4):print.           ; #20

; A send binds tighter than any operator, which is why the parentheses above are
; needed and why this is `#3 + (#4:negated)` rather than a sum being negated.
(#3 + #4:negated):print.          ; #-1

; Operators reach inside blocks, arrays and arguments, because the declaration
; is the module's rather than any expression's.
[#1 + #1, #2 * #2, #3 * #3]:print.    ; [#2, #4, #9]

integer:squared := { self * self }.
#7:squared:print.                 ; #49

; The prefix operator, and a loop written in it.
integer:sumTo := { | total, i |
    total := #0.
    i := #1.
    { ~(i > self) }:whileTrue({
        total := total + i.
        i := i + #1 }).
    total }.

#10:sumTo:print.                  ; #55
